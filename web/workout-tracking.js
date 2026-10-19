/* Strength workout entry upgrade: editable exercise names + sets while preserving existing records. */
(function () {
  function previousText(p) {
    if (!p) return '暂无上次记录';
    const sets = Number(p.sets) > 0 ? ` · ${Number(p.sets)} 组` : '';
    return `上次 ${p.date}：${Number(p.weight) || 0}kg × ${p.reps || '-'}${sets}`;
  }

  window.openWorkout = function openWorkout(split) {
    const rows = state.templates[split].map((name, i) => {
      const p = previous(name, split);
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
          <div class="suggestion">${p
            ? `今天先参考上次表现；如果所有工作组都稳定完成，再考虑下次小幅加重。`
            : '第一次记录，选择能稳定完成目标次数的重量。'}</div>
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
          <p class="subtle">动作名称可以直接修改。保存后会记住你的名称，下次继续使用。</p>
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

    // Persist customized exercise names as this split's template for future sessions.
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
