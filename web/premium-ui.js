/* App-first visual hierarchy: less dashboard chrome, stronger daily focus. */
(function(){
  const num=v=>{const n=Number(v);return Number.isFinite(n)?n:0;};
  const round=(v,d=0)=>{const p=10**d;return Math.round(num(v)*p)/p;};
  const clamp=(v,min=0,max=100)=>Math.max(min,Math.min(max,v));
  const goalPct=(value,goal)=>goal?clamp(value/goal*100):0;
  const totalMacros=list=>list.reduce((a,m)=>({
    calories:a.calories+num(m.calories),protein:a.protein+num(m.protein),
    carbs:a.carbs+num(m.carbs),fat:a.fat+num(m.fat)
  }),{calories:0,protein:0,carbs:0,fat:0});

  function macroRow(label,value,goal,unit){
    return `<div class="premium-macro-row"><div class="premium-macro-label"><span>${label}</span><strong>${round(value)}<small> / ${round(goal)}${unit}</small></strong></div><div class="premium-track"><i style="width:${goalPct(value,goal)}%"></i></div></div>`;
  }

  function recentMealRows(list){
    if(!list.length)return '<div class="premium-empty">今天还没有饮食记录</div>';
    return list.map((m,i)=>`<div class="premium-log-row"><div class="premium-log-index">${String(i+1).padStart(2,'0')}</div><div class="premium-log-copy"><strong>${esc(m.name||'一餐')}</strong><span>P ${round(m.protein)} · C ${round(m.carbs)} · F ${round(m.fat)}</span></div><div class="premium-log-value">${round(m.calories)}<small>kcal</small></div><button class="premium-delete" type="button" onclick="delMeal('${m.id}')" aria-label="删除这一餐">×</button></div>`).join('');
  }

  function movementRows(){
    const gym=gyms();const bad=bads();const rows=[];
    gym.forEach(w=>rows.push(`<div class="premium-move-row"><span class="premium-move-icon">◐</span><div><strong>${esc(w.split||w.name||'健身')}</strong><span>${round(w.minutes)} 分钟 · ${round(w.calories)} kcal</span></div></div>`));
    bad.forEach(w=>rows.push(`<div class="premium-move-row"><span class="premium-move-icon">◌</span><div><strong>羽毛球</strong><span>${round(w.minutes)} 分钟 · ${round(w.calories)} kcal</span></div></div>`));
    return rows.length?rows.join(''):'<div class="premium-empty">今天还没有运动记录</div>';
  }

  const premiumGreeting=function(){
    const h=new Date().getHours();
    const g=h<12?'早上好':h<18?'下午好':'晚上好';
    const title=document.querySelector('#greeting');
    const date=document.querySelector('#todayDate');
    if(title)title.textContent=`${g}，${state.profile.name||'多多'}`;
    if(date)date.textContent=new Date().toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'long'});
  };

  const premiumHome=function(){
    const m=meals(),tot=totalMacros(m),target=num(state.profile.calorieTarget)||2700;
    const proteinGoal=num(state.profile.proteinTarget)||130,fatGoal=num(state.profile.fatTarget)||70;
    const carbGoal=Math.max(0,(target-proteinGoal*4-fatGoal*9)/4);
    const remaining=Math.max(0,target-tot.calories);
    const active=sum(bads(),'calories')+sum(gyms(),'calories');
    const w=weight(),s=sleep(),next=nextSplit();
    return `<div class="premium-page premium-home">
      <section class="premium-overview">
        <div class="premium-energy">
          <div class="premium-kicker">TODAY</div>
          <div class="premium-energy-number"><strong>${round(remaining)}</strong><span>kcal<br>remaining</span></div>
          <div class="premium-energy-meta"><span>${round(tot.calories)} eaten</span><span>${target} target</span></div>
          <div class="premium-energy-bar"><i style="width:${goalPct(tot.calories,target)}%"></i></div>
          <div class="premium-macros">
            ${macroRow('Protein',tot.protein,proteinGoal,'g')}
            ${macroRow('Carbs',tot.carbs,carbGoal,'g')}
            ${macroRow('Fat',tot.fat,fatGoal,'g')}
          </div>
        </div>
        <aside class="premium-focus">
          <div><div class="premium-kicker">NEXT</div><h2>${next}训练</h2><p>${esc(coach())}</p></div>
          <div class="premium-focus-actions">
            <button type="button" class="premium-action primary-action" onclick="openMeal()"><span>＋</span><div><strong>记录饮食</strong><small>拍照识别</small></div></button>
            <button type="button" class="premium-action" onclick="setTab('training')"><span>▦</span><div><strong>打开日历</strong><small>查看训练与饮食</small></div></button>
          </div>
        </aside>
      </section>

      <section class="premium-status-strip">
        <div><span>体重</span><strong>${w?`${round(w.kg,1)} kg`:'--'}</strong></div>
        <div><span>活动消耗</span><strong>${round(active)} kcal</strong></div>
        <div><span>睡眠</span><strong>${s?`${round(s.hours,1)} h`:'--'}</strong></div>
        <div><span>今日饮食</span><strong>${m.length} 餐</strong></div>
      </section>

      <section class="premium-two-col">
        <div class="premium-section">
          <div class="premium-section-head"><div><span>FOOD</span><h3>今天吃了什么</h3></div><button type="button" onclick="setTab('nutrition')">查看全部</button></div>
          <div class="premium-log">${recentMealRows(m.slice(-4))}</div>
        </div>
        <div class="premium-section">
          <div class="premium-section-head"><div><span>TRAINING</span><h3>今天的运动</h3></div><button type="button" onclick="setTab('training')">日历</button></div>
          <div class="premium-movement">${movementRows()}</div>
        </div>
      </section>
    </div>`;
  };

  const premiumNutrition=function(){
    const m=meals(),tot=totalMacros(m),target=num(state.profile.calorieTarget)||2700;
    const proteinGoal=num(state.profile.proteinTarget)||130,fatGoal=num(state.profile.fatTarget)||70;
    const carbGoal=Math.max(0,(target-proteinGoal*4-fatGoal*9)/4);
    const remaining=Math.max(0,target-tot.calories);
    return `<div class="premium-page premium-nutrition">
      <section class="nutrition-topline">
        <div><div class="premium-kicker">NUTRITION</div><div class="nutrition-big"><strong>${round(tot.calories)}</strong><span>of ${target} kcal</span></div></div>
        <div class="nutrition-remaining"><strong>${round(remaining)}</strong><span>remaining</span></div>
      </section>
      <div class="nutrition-progress"><i style="width:${goalPct(tot.calories,target)}%"></i></div>
      <section class="nutrition-macro-grid">
        <div><span>Protein</span><strong>${round(tot.protein)}<small> / ${proteinGoal}g</small></strong><i><b style="width:${goalPct(tot.protein,proteinGoal)}%"></b></i></div>
        <div><span>Carbs</span><strong>${round(tot.carbs)}<small> / ${round(carbGoal)}g</small></strong><i><b style="width:${goalPct(tot.carbs,carbGoal)}%"></b></i></div>
        <div><span>Fat</span><strong>${round(tot.fat)}<small> / ${fatGoal}g</small></strong><i><b style="width:${goalPct(tot.fat,fatGoal)}%"></b></i></div>
      </section>
      <section class="nutrition-log-section">
        <div class="premium-section-head"><div><span>TODAY</span><h3>饮食记录</h3></div><div class="nutrition-actions"><button type="button" onclick="openManualMeal()">手动</button><button type="button" class="nutrition-camera" onclick="openMeal()">＋ 拍照记录</button></div></div>
        <div class="premium-log large-log">${recentMealRows(m)}</div>
      </section>
    </div>`;
  };

  try{window.greeting=premiumGreeting;greeting=premiumGreeting;}catch{window.greeting=premiumGreeting;}
  try{window.home=premiumHome;home=premiumHome;}catch{window.home=premiumHome;}
  try{window.nutrition=premiumNutrition;nutrition=premiumNutrition;}catch{window.nutrition=premiumNutrition;}
  if(typeof render==='function')render();
})();
