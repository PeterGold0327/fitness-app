/* Windows-first manual nutrition tracking extension.
   Keeps the existing localStorage schema and adds carbs/fat fields to meals. */
(function () {
  function macroTargets() {
    const protein = Number(state.profile.proteinTarget) || 130;
    const fat = Number(state.profile.fatTarget) || 70;
    const calories = Number(state.profile.calorieTarget) || 2700;
    const carbs = Math.max(0, (calories - protein * 4 - fat * 9) / 4);
    return { calories, protein, carbs, fat };
  }

  function mealTotals(list) {
    return {
      calories: sum(list, 'calories'),
      protein: sum(list, 'protein'),
      carbs: sum(list, 'carbs'),
      fat: sum(list, 'fat')
    };
  }

  function targetCalories(target) {
    return {
      protein: target.protein * 4,
      carbs: target.carbs * 4,
      fat: target.fat * 9
    };
  }

  window.openMeal = function openMeal() {
    modal(`
      <h2>记录今天吃的</h2>
      <div class="field">
        <label>吃了什么</label>
        <input id="mealName" placeholder="例如：米饭 + 鸡腿肉 + 西红柿炒蛋">
      </div>
      <div class="grid2">
        <div class="field"><label>热量 kcal</label><input id="mealCal" type="number" min="0" step="1" placeholder="例如 680"></div>
        <div class="field"><label>蛋白质 g</label><input id="mealPro" type="number" min="0" step="0.1" placeholder="例如 45"></div>
        <div class="field"><label>碳水 g</label><input id="mealCarbs" type="number" min="0" step="0.1" placeholder="例如 82"></div>
        <div class="field"><label>脂肪 g</label><input id="mealFat" type="number" min="0" step="0.1" placeholder="例如 18"></div>
      </div>
      <div class="surface-note">直接输入你今天实际吃的食物和大概营养值即可。四项都可以后续再补，不需要一次填得特别精确。</div>
      <button type="button" class="primary" onclick="saveMeal()">保存这一餐</button>
    `);
  };

  window.saveMeal = function saveMeal() {
    const name = document.querySelector('#mealName')?.value?.trim() || '一餐';
    const calories = Math.max(0, Number(document.querySelector('#mealCal')?.value) || 0);
    const protein = Math.max(0, Number(document.querySelector('#mealPro')?.value) || 0);
    const carbs = Math.max(0, Number(document.querySelector('#mealCarbs')?.value) || 0);
    const fat = Math.max(0, Number(document.querySelector('#mealFat')?.value) || 0);
    state.meals.push({ id: crypto.randomUUID(), date: key(), name, calories, protein, carbs, fat, source: 'manual-web' });
    closeModal();
    save();
  };

  window.nutrition = function nutrition() {
    const m = meals();
    const total = mealTotals(m);
    const target = macroTargets();
    const targetKcal = targetCalories(target);
    const remainingCalories = Math.max(0, target.calories - total.calories);
    const remainingProtein = Math.max(0, target.protein - total.protein);
    const remainingCarbs = Math.max(0, target.carbs - total.carbs);
    const remainingFat = Math.max(0, target.fat - total.fat);

    return `<div class="page-grid">
      <section class="card budget-card">
        <div class="ring" style="--p:${pct(total.calories,target.calories)}">
          <div class="ring-center"><div class="ring-value">${Math.round(remainingCalories)}</div><div class="ring-label">kcal 剩余</div></div>
        </div>
        <div class="budget-main">
          <div class="hero-kicker">TODAY'S NUTRITION</div>
          <h3>你的每日目标：${Math.round(target.calories)} kcal</h3>
          <p>按当前目标自动分配：蛋白质 ${Math.round(target.protein)}g、脂肪 ${Math.round(target.fat)}g，剩余热量给碳水，所以碳水约 ${Math.round(target.carbs)}g。</p>
          <div class="macro-row macro-row-four">
            <div class="macro"><strong>${Math.round(total.protein)} / ${Math.round(target.protein)}g</strong><span>蛋白质 · 还差 ${Math.round(remainingProtein)}g</span></div>
            <div class="macro"><strong>${Math.round(total.carbs)} / ${Math.round(target.carbs)}g</strong><span>碳水 · 还差 ${Math.round(remainingCarbs)}g</span></div>
            <div class="macro"><strong>${Math.round(total.fat)} / ${Math.round(target.fat)}g</strong><span>脂肪 · 还差 ${Math.round(remainingFat)}g</span></div>
            <div class="macro"><strong>${Math.round(total.calories)} / ${Math.round(target.calories)}</strong><span>总热量 kcal</span></div>
          </div>
        </div>
      </section>

      <section class="card">
        <div class="section-head"><div class="section-title">每天应该吃多少</div><span class="subtle">按当前 2700 kcal 目标自动计算</span></div>
        <div class="stat-strip">
          <div class="stat-card"><div class="stat-label">蛋白质</div><div class="stat-value">${Math.round(target.protein)}g</div><div class="stat-note">≈ ${Math.round(targetKcal.protein)} kcal</div></div>
          <div class="stat-card"><div class="stat-label">碳水</div><div class="stat-value">${Math.round(target.carbs)}g</div><div class="stat-note">≈ ${Math.round(targetKcal.carbs)} kcal</div></div>
          <div class="stat-card"><div class="stat-label">脂肪</div><div class="stat-value">${Math.round(target.fat)}g</div><div class="stat-note">≈ ${Math.round(targetKcal.fat)} kcal</div></div>
          <div class="stat-card"><div class="stat-label">总热量</div><div class="stat-value">${Math.round(target.calories)}</div><div class="stat-note">kcal / 天</div></div>
        </div>
        <div class="surface-note" style="margin-top:14px">计算方式：蛋白质 4 kcal/g、碳水 4 kcal/g、脂肪 9 kcal/g。当前默认是蛋白质 ${Math.round(target.protein)}g + 脂肪 ${Math.round(target.fat)}g，碳水自动补足到 ${Math.round(target.calories)} kcal。</div>
      </section>

      <button class="primary" onclick="openMeal()">＋ 手动记录今天吃的</button>

      <section class="card">
        <div class="section-head"><div class="section-title">今天吃了什么</div><span class="subtle">${m.length} 餐</span></div>
        ${m.length ? m.map(x => `<div class="meal-item">
          <div class="meal-icon">🍽</div>
          <div class="meal-main">
            <div class="meal-name">${esc(x.name)}</div>
            <div class="meal-meta">${Math.round(Number(x.calories)||0)} kcal · 蛋白质 ${Math.round(Number(x.protein)||0)}g · 碳水 ${Math.round(Number(x.carbs)||0)}g · 脂肪 ${Math.round(Number(x.fat)||0)}g</div>
          </div>
          <button class="text-btn" onclick="delMeal('${x.id}')">删除</button>
        </div>`).join('') : '<div class="empty">今天还没有饮食记录</div>'}
      </section>
    </div>`;
  };

  /* Keep the quick-add and any existing callers pointing at the new manual form. */
  document.querySelector('#quickAdd')?.addEventListener('click', function () {
    setTimeout(() => window.openMeal(), 0);
  }, { once: true });

  if (typeof render === 'function') render();
})();
