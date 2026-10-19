/* Hypertrophy workout entry: editable names, per-set load/reps/RPE, history-based guidance. */
(function () {
  function clampRpe(value) {
    const n = Number(value);
    return Number.isFinite(n) && n >= 1 && n <= 10 ? n : 0;
  }

  function normalizeSetEntries(exercise) {
    if (!exercise) return [];
    if (Array.isArray(exercise.setEntries) && exercise.setEntries.length) {
      return exercise.setEntries
        .map((s, i) => ({
          order: i + 1,
          weight: Math.max(0, Number(s.weight) || 0),
          reps: Math.max(0, Math.round(Number(s.reps) || 0)),
          rpe: clampRpe(s.rpe)
        }))
        .filter(s => s.weight || s.reps || s.rpe);
    }
    const reps = String(exercise.reps || '')
      .split(/[\/，,\s]+/)
      .map(Number)
      .filter(n => Number.isFinite(n) && n > 0);
    const count = Math.max(Number(exercise.sets) || 0, reps.length, exercise.weight ? 1 : 0);
    return Array.from({ length: count }, (_, i) => ({
      order: i + 1,
      weight: Math.max(0, Number(exercise.weight) || 0),
      reps: reps[i] || 0,
      rpe: 0
    }));
  }

  function exerciseHistory(split, name, index) {
    const sessions = [...state.workouts]
      .filter(x => x.split === split)
      .sort((a, b) => b.date.localeCompare(a.date));
    const found = [];
    for (const session of sessions) {
      const exercises = session.exercises || [];
      let exercise = exercises.find(x => x.name === name);
      // Keep history even when the user renames the exercise in the same template slot.
      if (!exercise && exercises[index]) exercise = exercises[index];
      if (exercise) found.push({ date: session.date, ...exercise, setEntries: normalizeSetEntries(exercise) });
      if (found.length >= 4) break;
    }
    return found;
  }

  function hypertrophyProfile(name) {
    const n = String(name || '').toLowerCase();
    const highRep = [
      '侧平举','反向飞鸟','飞鸟','夹胸','面拉','小腿','提踵','弯举','下压','臂屈伸','腿弯举','腿屈伸','绳索','核心',
      'lateral','raise','fly','curl','pushdown','extension','calf','rear delt','face pull'
    ];
    const compound = [
      '卧推','胸推','肩推','深蹲','腿举','哈克','硬拉','罗马尼亚','分腿蹲','划船','下拉','引体','推举',
      'bench','press','squat','deadlift','row','pulldown','pull-up','leg press','hack'
    ];
    if (highRep.some(k => n.includes(k))) {
      return { min: 10, max: 20, label: '孤立/小肌群', rpe: '8–9' };
    }
    if (compound.some(k => n.includes(k))) {
      return { min: 6, max: 12, label: '复合动作', rpe: '8–9' };
    }
    return { min: 8, max: 15, label: '通用增肌', rpe: '8–9' };
  }

  function setsText(exercise) {
    const entries = normalizeSetEntries(exercise);
    if (!entries.length) return '暂无上次记录';
    return entries.map((s, i) => {
      const rpe = s.rpe ? ` @RPE${s.rpe}` : '';
      return `第${i + 1}组 ${s.weight}kg × ${s.reps || '-'}${rpe}`;
    }).join(' · ');
  }

  function workingSets(entries) {
    const completed = entries.filter(s => s.weight > 0 && s.reps > 0);
    if (!completed.length) return [];
    const byRpe = completed.filter(s => s.rpe >= 7);
    if (byRpe.length) return byRpe;
    const top = Math.max(...completed.map(s => s.weight));
    return completed.filter(s => s.weight >= top * 0.85);
  }

  function average(values) {
    return values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0;
  }

  function loadStep(weight) {
    if (weight < 20) return 0.5;
    if (weight < 60) return 1;
    return 2.5;
  }

  function roundToStep(value, step) {
    return Math.round(value / step) * step;
  }

  function nextLoad(weight, pct) {
    const step = loadStep(weight);
    const proposed = roundToStep(weight * (1 + pct), step);
    return Math.max(weight + step, proposed);
  }

  function lowerLoad(weight, pct) {
    const step = loadStep(weight);
    return Math.max(step, roundToStep(weight * (1 - pct), step));
  }

  function overloadSuggestion(history, name) {
    const profile = hypertrophyProfile(name);
    const range = `${profile.min}–${profile.max} 次`;
    if (!history.length) {
      return `第一次记录：工作组先以 ${range} 为主，RPE 8–9（大约保留 1–2 次余力）。先找稳定重量，不需要每组做到力竭。`;
    }

    const last = history[0];
    const current = workingSets(normalizeSetEntries(last));
    if (!current.length) {
      return `下次把工作组控制在 ${range}、RPE 8–9，并记录每一组 RPE；有了完整数据后会按上次重量自动调整。`;
    }

    const topWeight = Math.max(...current.map(s => s.weight));
    const topSets = current.filter(s => s.weight === topWeight);
    const reps = topSets.map(s => s.reps).filter(Boolean);
    const rpes = topSets.map(s => s.rpe).filter(Boolean);
    const avgReps = average(reps);
    const avgRpe = average(rpes);
    const minReps = reps.length ? Math.min(...reps) : 0;
    const maxReps = reps.length ? Math.max(...reps) : 0;
    const gentleUp = nextLoad(topWeight, 0.025);
    const smallDown = lowerLoad(topWeight, 0.025);

    if (!rpes.length) {
      return `上次最高工作重量 ${topWeight}kg。下次先沿用 ${topWeight}kg，目标 ${range}、RPE 8–9；请记录 RPE，之后我会同时按重量、次数和接近力竭程度给建议。`;
    }

    if ((avgRpe >= 9.5 && avgReps < profile.min) || (minReps && minReps < profile.min - 1)) {
      return `上次 ${topWeight}kg 偏重（平均约 RPE ${avgRpe.toFixed(1)}，次数偏低）。下次最高工作组可先降到约 ${smallDown}kg，回到 ${range}，目标 RPE 8–9。`;
    }

    if (minReps >= profile.max && avgRpe <= 9) {
      return `上次 ${topWeight}kg 已让工作组稳定达到 ${profile.max} 次左右，平均 RPE ${avgRpe.toFixed(1)}。下次可尝试约 ${gentleUp}kg，回到 ${profile.min}–${Math.min(profile.min + 3, profile.max)} 次，RPE 8–9。`;
    }

    if (avgRpe <= 7.5 && avgReps >= (profile.min + profile.max) / 2) {
      return `上次 ${topWeight}kg 明显还有余力（平均 RPE ${avgRpe.toFixed(1)}）。下次可小幅加到约 ${gentleUp}kg，仍以 ${range}、RPE 8–9 为目标。`;
    }

    if (avgRpe >= 9.5 && maxReps >= profile.min) {
      return `上次 ${topWeight}kg 已接近力竭（平均 RPE ${avgRpe.toFixed(1)}）。这次先保持 ${topWeight}kg，不急着加重，争取用更稳定动作完成 ${range}，多数工作组控制在 RPE 8–9。`;
    }

    const targetRep = Math.min(profile.max, Math.max(profile.min, Math.round(avgReps + 1)));
    return `上次最高工作重量 ${topWeight}kg，平均约 ${avgReps.toFixed(1)} 次 @RPE ${avgRpe.toFixed(1)}。下次先保持 ${topWeight}kg，目标把工作组推进到约 ${targetRep} 次，RPE 8–9；达到区间上沿后再小幅加重。`;
  }

  function renderSetRows(exerciseIndex, entries) {
    const rows = entries.length ? entries : [
      { weight: 0, reps: 0, rpe: 0 },
      { weight: 0, reps: 0, rpe: 0 },
      { weight: 0, reps: 0, rpe: 0 }
    ];
    return rows.map((set, setIndex) => `
      <div class="set-row" data-exercise="${exerciseIndex}" data-set="${setIndex}">
        <div class="set-number">${setIndex + 1}</div>
        <div class="input-with-unit"><input class="set-weight" type="number" min="0" step="0.5" value="${set.weight || ''}" placeholder="重量"><span>kg</span></div>
        <div class="input-with-unit"><input class="set-reps" type="number" min="0" step="1" value="${set.reps || ''}" placeholder="次数"><span>次</span></div>
        <div class="input-with-unit rpe-input"><input class="set-rpe" type="number" min="6" max="10" step="0.5" value="" placeholder="8–9"><span>RPE</span></div>
        <button type="button" class="set-remove" onclick="window.removeWorkoutSet(this)" aria-label="删除这一组">×</button>
      </div>`).join('');
  }

  window.addWorkoutSet = function addWorkoutSet(exerciseIndex) {
    const list = document.querySelector(`#sets-${exerciseIndex}`);
    if (!list) return;
    const count = list.querySelectorAll('.set-row').length;
    const row = document.createElement('div');
    row.className = 'set-row';
    row.dataset.exercise = exerciseIndex;
    row.dataset.set = count;
    row.innerHTML = `
      <div class="set-number">${count + 1}</div>
      <div class="input-with-unit"><input class="set-weight" type="number" min="0" step="0.5" placeholder="重量"><span>kg</span></div>
      <div class="input-with-unit"><input class="set-reps" type="number" min="0" step="1" placeholder="次数"><span>次</span></div>
      <div class="input-with-unit rpe-input"><input class="set-rpe" type="number" min="6" max="10" step="0.5" placeholder="8–9"><span>RPE</span></div>
      <button type="button" class="set-remove" onclick="window.removeWorkoutSet(this)" aria-label="删除这一组">×</button>`;
    list.appendChild(row);
  };

  window.removeWorkoutSet = function removeWorkoutSet(button) {
    const row = button.closest('.set-row');
    const list = row?.parentElement;
    if (!row || !list) return;
    if (list.querySelectorAll('.set-row').length <= 1) return;
    row.remove();
    [...list.querySelectorAll('.set-row')].forEach((r, i) => {
      r.dataset.set = i;
      const n = r.querySelector('.set-number');
      if (n) n.textContent = i + 1;
    });
  };

  window.openWorkout = function openWorkout(split) {
    const rows = state.templates[split].map((name, i) => {
      const history = exerciseHistory(split, name, i);
      const p = history[0];
      const previousSets = p ? normalizeSetEntries(p) : [];
      const profile = hypertrophyProfile(name);
      return `
        <section class="workout-exercise-card">
          <div class="workout-exercise-head">
            <div class="exercise-title-edit">
              <label class="tiny">动作名称</label>
              <input id="n${i}" class="exercise-name-input" value="${esc(name)}" placeholder="输入动作名称">
              <div class="hypertrophy-target">${profile.label} · 建议 ${profile.min}–${profile.max} 次 · RPE ${profile.rpe}</div>
              <div class="previous">${p ? `上次 ${p.date}：${setsText(p)}` : '暂无上次记录'}</div>
            </div>
            <span class="exercise-index">${String(i + 1).padStart(2, '0')}</span>
          </div>
          <div class="suggestion"><strong>本次增肌建议：</strong>${overloadSuggestion(history, name)}</div>
          <div class="set-table-head"><span>组</span><span>重量</span><span>次数</span><span>RPE</span><span></span></div>
          <div id="sets-${i}" class="set-list">${renderSetRows(i, previousSets)}</div>
          <button type="button" class="secondary add-set-btn" onclick="window.addWorkoutSet(${i})">＋ 添加一组</button>
        </section>`;
    }).join('');

    modal(`
      <div class="workout-modal-head">
        <div>
          <div class="hero-kicker">HYPERTROPHY WORKOUT</div>
          <h2>${split}训练</h2>
          <p class="subtle">目标不是机械 double progression：系统会结合上一次每组重量、次数和 RPE 给下一次建议。大多数工作组保持 RPE 8–9（约留 1–2 次余力）。</p>
        </div>
        <span class="pill">${state.templates[split].length} 个动作</span>
      </div>
      <div class="rpe-guide"><strong>RPE：</strong><span>7 ≈ 还能做 3 次</span><span>8 ≈ 还能做 2 次</span><span>9 ≈ 还能做 1 次</span><span>10 = 基本力竭</span></div>
      <div class="workout-exercise-list">${rows}</div>
      <section class="workout-session-card">
        <div class="section-title">本次训练</div>
        <div class="grid2">
          <div class="field"><label>时长（分钟）</label><input id="gymMinutes" type="number" min="0" value="75"></div>
          <div class="field"><label>活动消耗 kcal</label><input id="gymCalories" type="number" min="0" value="0"></div>
        </div>
      </section>
      <button type="button" class="primary workout-save" onclick="saveWorkout('${split}')">保存本次训练</button>
    `);
  };

  window.saveWorkout = function saveWorkout(split) {
    const editedNames = state.templates[split].map((oldName, i) => {
      const value = document.querySelector('#n' + i)?.value?.trim();
      return value || oldName;
    });

    const exercises = editedNames.map((name, i) => {
      const rows = [...document.querySelectorAll(`#sets-${i} .set-row`)];
      const setEntries = rows.map((row, idx) => ({
        order: idx + 1,
        weight: Math.max(0, Number(row.querySelector('.set-weight')?.value) || 0),
        reps: Math.max(0, Math.round(Number(row.querySelector('.set-reps')?.value) || 0)),
        rpe: clampRpe(row.querySelector('.set-rpe')?.value)
      })).filter(s => s.weight || s.reps || s.rpe);
      const maxWeight = setEntries.length ? Math.max(...setEntries.map(s => s.weight)) : 0;
      return {
        name,
        setEntries,
        sets: setEntries.length,
        weight: maxWeight,
        reps: setEntries.map(s => s.reps || '').join('/'),
        averageRpe: average(setEntries.map(s => s.rpe).filter(Boolean)) || 0
      };
    }).filter(x => x.setEntries.length);

    state.templates[split] = editedNames;
    state.workouts.push({
      id: crypto.randomUUID(),
      date: key(),
      split,
      minutes: Math.max(0, Number(document.querySelector('#gymMinutes')?.value) || 0),
      calories: Math.max(0, Number(document.querySelector('#gymCalories')?.value) || 0),
      exercises
    });
    closeModal();
    save();
  };

  if (typeof render === 'function') render();
})();
