/* Strength workout entry: editable exercise names, per-set weights/reps, history and progressive overload. */
(function () {
  function normalizeSetEntries(exercise) {
    if (!exercise) return [];
    if (Array.isArray(exercise.setEntries) && exercise.setEntries.length) {
      return exercise.setEntries
        .map((s, i) => ({
          order: i + 1,
          weight: Math.max(0, Number(s.weight) || 0),
          reps: Math.max(0, Math.round(Number(s.reps) || 0))
        }))
        .filter(s => s.weight || s.reps);
    }
    const reps = String(exercise.reps || '')
      .split(/[\/，,\s]+/)
      .map(Number)
      .filter(n => Number.isFinite(n) && n > 0);
    const count = Math.max(Number(exercise.sets) || 0, reps.length, exercise.weight ? 1 : 0);
    return Array.from({ length: count }, (_, i) => ({
      order: i + 1,
      weight: Math.max(0, Number(exercise.weight) || 0),
      reps: reps[i] || 0
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
      if (!exercise && exercises[index]) exercise = exercises[index];
      if (exercise) found.push({ date: session.date, ...exercise, setEntries: normalizeSetEntries(exercise) });
      if (found.length >= 3) break;
    }
    return found;
  }

  function setsText(exercise) {
    const entries = normalizeSetEntries(exercise);
    if (!entries.length) return '暂无上次记录';
    return entries.map((s, i) => `第${i + 1}组 ${s.weight}kg × ${s.reps || '-'}`).join(' · ');
  }

  function incrementFor(weight) {
    const w = Number(weight) || 0;
    if (w <= 20) return 1;
    if (w <= 50) return 2;
    return 2.5;
  }

  function overloadSuggestion(history) {
    if (!history.length) return '第一次记录：每一组分别记录实际重量和次数。下次我会按这个动作自己的每组表现给建议。';
    const last = history[0];
    const current = normalizeSetEntries(last);
    if (!current.length) return '先按实际完成记录每组重量和次数，下次再根据这个动作自己的历史做渐进。';

    const heaviest = Math.max(...current.map(s => s.weight));
    const heavySets = current.filter(s => s.weight === heaviest && s.reps > 0);
    const previous = history[1] ? normalizeSetEntries(history[1]) : [];
    const previousHeavy = previous.filter(s => s.weight === heaviest && s.reps > 0);
    const jump = incrementFor(heaviest);

    if (heavySets.length && heavySets.every(s => s.reps >= 12)) {
      return `上次最高工作重量 ${heaviest}kg 的各组都达到约 12 次，可以考虑把这些工作组提高到约 ${(heaviest + jump).toFixed(1)}kg；热身组和较轻组不用强行加重。`;
    }

    if (previousHeavy.length && heavySets.length) {
      const nowTotal = heavySets.reduce((a, s) => a + s.reps, 0);
      const prevTotal = previousHeavy.reduce((a, s) => a + s.reps, 0);
      if (nowTotal > prevTotal) {
        return `最高工作重量 ${heaviest}kg 的总次数在进步。下次保留各组不同重量，优先让同重量工作组再多 1 次左右。`;
      }
    }

    const top = heavySets[0] || current[current.length - 1];
    return `保持你自己的递增/递减组重量安排。下次重点让 ${top.weight}kg 的工作组比上次多 1 次左右；达到目标次数后再小幅加重。`;
  }

  function renderSetRows(exerciseIndex, entries) {
    const rows = entries.length ? entries : [
      { weight: 0, reps: 0 }, { weight: 0, reps: 0 }, { weight: 0, reps: 0 }
    ];
    return rows.map((set, setIndex) => `
      <div class="set-row" data-exercise="${exerciseIndex}" data-set="${setIndex}">
        <div class="set-number">${setIndex + 1}</div>
        <div class="input-with-unit"><input class="set-weight" type="number" min="0" step="0.5" value="${set.weight || ''}" placeholder="重量"><span>kg</span></div>
        <div class="input-with-unit"><input class="set-reps" type="number" min="0" step="1" value="${set.reps || ''}" placeholder="次数"><span>次</span></div>
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
      return `
        <section class="workout-exercise-card">
          <div class="workout-exercise-head">
            <div class="exercise-title-edit">
              <label class="tiny">动作名称</label>
              <input id="n${i}" class="exercise-name-input" value="${esc(name)}" placeholder="输入动作名称">
              <div class="previous">${p ? `上次 ${p.date}：${setsText(p)}` : '暂无上次记录'}</div>
            </div>
            <span class="exercise-index">${String(i + 1).padStart(2, '0')}</span>
          </div>
          <div class="suggestion"><strong>渐进建议：</strong>${overloadSuggestion(history)}</div>
          <div class="set-table-head"><span>组</span><span>重量</span><span>次数</span><span></span></div>
          <div id="sets-${i}" class="set-list">${renderSetRows(i, previousSets)}</div>
          <button type="button" class="secondary add-set-btn" onclick="window.addWorkoutSet(${i})">＋ 添加一组</button>
        </section>`;
    }).join('');

    modal(`
      <div class="workout-modal-head">
        <div>
          <div class="hero-kicker">STRENGTH WORKOUT</div>
          <h2>${split}训练</h2>
          <p class="subtle">同一个动作的每一组都可以使用不同重量。系统会分别保存每组重量和次数，并按工作组历史做渐进超负荷建议。</p>
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
      const rows = [...document.querySelectorAll(`#sets-${i} .set-row`)];
      const setEntries = rows.map((row, idx) => ({
        order: idx + 1,
        weight: Math.max(0, Number(row.querySelector('.set-weight')?.value) || 0),
        reps: Math.max(0, Math.round(Number(row.querySelector('.set-reps')?.value) || 0))
      })).filter(s => s.weight || s.reps);
      const maxWeight = setEntries.length ? Math.max(...setEntries.map(s => s.weight)) : 0;
      return {
        name,
        setEntries,
        sets: setEntries.length,
        weight: maxWeight,
        reps: setEntries.map(s => s.reps || '').join('/')
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
