/* Daily history browser for nutrition, foods, training and activity. */
(function(){
  let historyMode='all';
  let historyLimit=30;

  function n(v){const x=Number(v);return Number.isFinite(x)?x:0;}
  function round(v,d=0){const p=10**d;return Math.round(n(v)*p)/p;}
  function dateLabel(date){
    try{return new Date(date+'T12:00:00').toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'short'});}catch{return date;}
  }
  function totals(meals){return meals.reduce((a,m)=>({
    calories:a.calories+n(m.calories),protein:a.protein+n(m.protein),carbs:a.carbs+n(m.carbs),fat:a.fat+n(m.fat)
  }),{calories:0,protein:0,carbs:0,fat:0});}

  function allDates(){
    const set=new Set();
    for(const list of [state.meals||[],state.workouts||[],state.badminton||[],state.weights||[],state.sleep||[]]){
      for(const x of list)if(x?.date)set.add(x.date);
    }
    return [...set].sort((a,b)=>b.localeCompare(a));
  }

  function mealFoods(meal){
    if(Array.isArray(meal.items)&&meal.items.length){
      return `<div class="history-food-list">${meal.items.map(item=>`<div class="history-food-row"><span>${esc(item.name||'食物')}${n(item.grams)?` · ${round(item.grams)}g`:''}</span><span>${round(item.calories)} kcal · P ${round(item.protein)} · C ${round(item.carbs)} · F ${round(item.fat)}</span></div>`).join('')}</div>`;
    }
    return '';
  }

  function nutritionBlock(date){
    const meals=(state.meals||[]).filter(x=>x.date===date);
    if(!meals.length)return '<div class="history-empty-mini">这天没有饮食记录</div>';
    const t=totals(meals);
    return `<div class="history-nutrition">
      <div class="history-macros">
        <div><strong>${round(t.calories)}</strong><span>kcal</span></div>
        <div><strong>${round(t.protein)}g</strong><span>蛋白质</span></div>
        <div><strong>${round(t.carbs)}g</strong><span>碳水</span></div>
        <div><strong>${round(t.fat)}g</strong><span>脂肪</span></div>
      </div>
      <div class="history-meals">${meals.map((m,i)=>`<div class="history-meal-card">
        <div class="history-meal-head"><div><span class="history-meal-index">${i+1}</span><strong>${esc(m.name||'一餐')}</strong></div><span>${round(m.calories)} kcal</span></div>
        <div class="history-meal-macros">P ${round(m.protein)}g · C ${round(m.carbs)}g · F ${round(m.fat)}g</div>
        ${mealFoods(m)}
      </div>`).join('')}</div>
    </div>`;
  }

  function activityBlock(date){
    const workouts=(state.workouts||[]).filter(x=>x.date===date);
    const badminton=(state.badminton||[]).filter(x=>x.date===date);
    if(!workouts.length&&!badminton.length)return '<div class="history-empty-mini">这天没有运动记录</div>';
    return `<div class="history-activity-list">
      ${workouts.map(w=>`<div class="history-activity-row"><div><strong>🏋 ${esc(w.split||w.name||'力量训练')}</strong><span>${(w.exercises||[]).map(e=>esc(e.name)).slice(0,5).join(' · ')||'训练记录'}</span></div><div>${n(w.minutes)?`${round(w.minutes)} 分钟`:''}${n(w.calories)?` · ${round(w.calories)} kcal`:''}</div></div>`).join('')}
      ${badminton.map(b=>`<div class="history-activity-row"><div><strong>🏸 羽毛球</strong><span>${b.source==='iphone-archive'?'iPhone 历史记录':'运动记录'}</span></div><div>${n(b.minutes)?`${round(b.minutes)} 分钟`:''}${n(b.calories)?` · ${round(b.calories)} kcal`:''}</div></div>`).join('')}
    </div>`;
  }

  function dayCard(date){
    const w=(state.weights||[]).find(x=>x.date===date);
    const s=(state.sleep||[]).find(x=>x.date===date);
    const meals=(state.meals||[]).filter(x=>x.date===date);
    const t=totals(meals);
    return `<details class="history-day" ${date===key()?'open':''}>
      <summary>
        <div><strong>${dateLabel(date)}</strong><span>${date}</span></div>
        <div class="history-day-summary">
          ${meals.length?`<span>${round(t.calories)} kcal</span><span>P ${round(t.protein)}g</span>`:''}
          ${w?`<span>${round(w.kg,1)} kg</span>`:''}
          ${s?`<span>睡眠 ${round(s.hours,1)}h</span>`:''}
        </div>
      </summary>
      <div class="history-day-body">
        ${historyMode!=='activity'?`<section><div class="history-subtitle">营养与食物</div>${nutritionBlock(date)}</section>`:''}
        ${historyMode!=='nutrition'?`<section><div class="history-subtitle">运动</div>${activityBlock(date)}</section>`:''}
      </div>
    </details>`;
  }

  function historyHtml(){
    const dates=allDates().slice(0,historyLimit);
    return `<section class="card history-browser">
      <div class="section-head history-main-head">
        <div><div class="hero-kicker">HISTORY</div><div class="section-title">历史记录</div><div class="subtle">按天查看你吃了什么、当天营养总量和运动记录</div></div>
        <div class="history-filters">
          <button type="button" class="secondary ${historyMode==='all'?'history-active':''}" onclick="window.setHistoryMode('all')">全部</button>
          <button type="button" class="secondary ${historyMode==='nutrition'?'history-active':''}" onclick="window.setHistoryMode('nutrition')">饮食</button>
          <button type="button" class="secondary ${historyMode==='activity'?'history-active':''}" onclick="window.setHistoryMode('activity')">运动</button>
        </div>
      </div>
      ${dates.length?`<div class="history-days">${dates.map(dayCard).join('')}</div>`:'<div class="empty">还没有历史记录</div>'}
      ${allDates().length>historyLimit?`<button type="button" class="secondary history-more" onclick="window.showMoreHistory()">显示更早记录</button>`:''}
    </section>`;
  }

  window.setHistoryMode=function(mode){historyMode=mode;render();};
  window.showMoreHistory=function(){historyLimit+=30;render();};
  window.openHistory=function(mode='all'){historyMode=mode;tab='progress';render();};

  const originalProgress=window.progress;
  if(typeof originalProgress==='function'){
    window.progress=function progressWithHistory(){return originalProgress()+historyHtml();};
  }

  const originalNutrition=window.nutrition;
  if(typeof originalNutrition==='function'){
    window.nutrition=function nutritionWithHistoryShortcut(){
      const html=originalNutrition();
      return html.replace('</div>',`<button type="button" class="secondary history-shortcut" onclick="openHistory('nutrition')">查看每天的历史饮食 →</button></div>`);
    };
  }

  if(typeof render==='function')render();
})();
