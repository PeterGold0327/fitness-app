/* Strength workout entry: editable exercise names, per-exercise history, sets, reps and progressive overload. */
(function () {
  function repsArray(value) {
    return String(value || '')
      .split(/[\/，,\s]+/)
      .map(Number)
      .filter(n => Number.isFinite(n) && n > 0);
  }

  function totalReps(value) {
    return repsArray(value).reduce((a, b) => a + b, 0);
  }

  function exerciseHistory(split, name, index) {
    const sessions = [...state.workouts]
      .filter(x => x.split === split)
      .sort((a, b) => b.date.localeCompare(a.date));

    const found = [];
    for (const session of sessions) {
      const exercises = session.exercises || [];
      let exercise = exercises.find(x => x.name === name);
      // Fallback by template position so renaming an exercise does not destroy its history.
      if (!exercise && exercises[index]) exercise = exercises[index];
      if (exercise) found.push({ date: session.date, ...exercise });
      if (found.length >= 3) break;
    }
    return found;
  }

  function previousText(p) {
    if (!p) return '暂无上次记录';
    const sets = Number(p.sets) > 0 ? ` · ${Number(p.sets)}组` : '';
    return `上次 ${p.date}：${Number(p.weight) || 0}kg × ${p.reps || '-'}${sets}`;
  }

  function incrementFor(weight) {
    const w = Number(weight) || 0;
    if (w <= 20) return 1;
    if (w <= 50) return 2;
    return 2.5;
  }

  function overloadSuggestion(history) {
    if (!history.length) return '第一次记录：先找到能稳定完成各组的重量，之后再逐步增加次数或重量。';

    const last = history[0];
    const prev = history[1];
    const weight = Number(last.weight) || 0;
    const sets = Number(last.sets) || repsArray(last.reps).length || 3;
    const reps = repsArray(last.reps);
    const minRep = reps.length ? Math.min(...reps) : 0;
    const maxRep = reps.length ? Math.max(...reps) : 0;
    const nextJump = incrementFor(weight);

    if (!reps.length) {
      return `今天先从 ${weight || '上次'}kg 开始，完成后记录每组次数，我会按这个动作自己的历史给下次建议。`;
    }

    if (minRep >= 12 && sets > 0) {
      return `这个动作上次各组都达到 12 次，可尝试约 ${Number((weight + nextJump).toFixed(1))}kg；加重后次数下降一点是正常的。`;
    }

    if (prev && Number(prev.weight) === weight && totalReps(last.reps) > totalReps(prev.reps)) {
      return `这个动作同重量总次数在上升。今天继续 ${weight}kg，争取再多 1–2 次；稳定到每组约 12 次再加重。`;
    }

    if (maxRep >= 10) {
      return `今天继续 ${weight}kg，优先把较低的组数补上；当各组都稳定到约 12 次，再加 ${nextJump}kg 左右。`;
    }

    return `今天先保持 ${weight}kg，目标比上次总次数多 1–2 次。先加次数，再加重量。`;
  }

  window.openWorkout = function openWorkout(split) {
    const rows = state.templates[split].map((name, i) => {
      const history = exerciseHistory(split, name, i);
      const p = history[0];
      const defaultSets = Number(p?.sets) > 0 ? Number(p.sets) : 3;
      return `
        <section class="workout-exercise-card">
          <div class="workout-exercise-head">
            <div class="exercise-title-edit">
              <label class="tiny">动作名称</label>
              <input id="n${i}" class="exercise-name-input" value="${esc(name)}" placeholder="输入动作名称">
              <div class="previous">${previousText(p)}</div>
            </div>
            <span class="exercise-index">${String(i + 1).padStart(2, '0')}</span>
          </div>
          <div class="suggestion"><strong>渐进建议：</strong>${overloadSuggestion(history)}</div>
          <div class="workout-input-grid">
            <div class="field">
              <label>重量</label>
              <div class="input-with-unit"><input id="w${i}" type="number" min="0" step="0.5" value="${p?.weight || ''}" placeholder="0"><span>kg</span></div>
            </div>
            <div class="field">
              <label>组数</label>
              <div class="input-with-unit"><input id="s${i}" type="number" min="1" max="20" step="1" value="${defaultSets}"><span>组</span></div>
            </div>
            <div class="field reps-field">
              <label>每组次数</label>
              <input id="r${i}" value="${p?.reps || ''}" placeholder="例如 10/10/9">
            </div>
          </div>
        </section>`;
    }).join('');

    modal(`
      <div class="workout-modal-head">
        <div>
          <div class="hero-kicker">STRENGTH WORKOUT</div>
          <h2>${split}训练</h2>
          <p class="subtle">每个动作单独记忆自己的重量、组数和次数，并根据它自己的历史做渐进超负荷建议。</p>
        </div>
        <span class="pill">${state.templates[split].length} 个动作</span>
      </div>
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
      const weight = Math.max(0, Number(document.querySelector('#w' + i)?.value) || 0);
      const sets = Math.max(0, Math.round(Number(document.querySelector('#s' + i)?.value) || 0));
      const reps = document.querySelector('#r' + i)?.value.trim() || '';
      return { name, weight, sets, reps };
    }).filter(x => x.weight || x.reps || x.sets);

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
