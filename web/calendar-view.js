/* Calendar-first activity view: click a day to inspect training, badminton, nutrition and health. */
(function(){
  const pad=n=>String(n).padStart(2,'0');
  const localDateKey=(d=new Date())=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;

  // The original app used toISOString(), which can shift Brisbane morning records to the previous UTC date.
  // Replace the global date key with a true local calendar date before new records are created.
  window.key=localDateKey;

  const today=()=>localDateKey(new Date());
  let selectedDate=today();
  let cursorYear=new Date().getFullYear();
  let cursorMonth=new Date().getMonth()+1;

  const num=v=>{const n=Number(v);return Number.isFinite(n)?n:0;};
  const round=(v,d=0)=>{const p=10**d;return Math.round(num(v)*p)/p;};
  const html=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const dateParts=date=>{const [y,m,d]=String(date).split('-').map(Number);return {y,m,d};};
  const monthKey=(y,m)=>`${y}-${pad(m)}`;
  const monthTitle=(y,m)=>`${y}年 ${m}月`;
  const dayLabel=date=>{const {y,m,d}=dateParts(date);const dt=new Date(y,m-1,d);return dt.toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'long'});};

  function listFor(date){
    return {
      meals:(state.meals||[]).filter(x=>x.date===date),
      workouts:(state.workouts||[]).filter(x=>x.date===date),
      badminton:(state.badminton||[]).filter(x=>x.date===date),
      healthWorkouts:(state.health?.workouts||[]).filter(x=>x.date===date),
      health:state.health?.daily?.[date]||null,
      weight:(state.weights||[]).find(x=>x.date===date)||null,
      sleep:(state.sleep||[]).find(x=>x.date===date)||null
    };
  }

  function mealTotals(meals){
    return meals.reduce((a,m)=>({
      calories:a.calories+num(m.calories),protein:a.protein+num(m.protein),
      carbs:a.carbs+num(m.carbs),fat:a.fat+num(m.fat)
    }),{calories:0,protein:0,carbs:0,fat:0});
  }

  function hasData(date){
    const x=listFor(date);
    return x.meals.length||x.workouts.length||x.badminton.length||x.healthWorkouts.length||x.health||x.weight||x.sleep;
  }

  function daySignals(date){
    const x=listFor(date);
    const signals=[];
    if(x.workouts.length)signals.push(`<span class="cal-signal strength">🏋 ${html(x.workouts[0].split||'力量')}</span>`);
    if(x.badminton.length)signals.push('<span class="cal-signal badminton">🏸</span>');
    if(x.meals.length)signals.push(`<span class="cal-signal meal">🍴 ${x.meals.length}</span>`);
    if(x.healthWorkouts.length)signals.push('<span class="cal-signal watch">⌚</span>');
    return signals.slice(0,3).join('');
  }

  function calendarGrid(){
    const first=new Date(cursorYear,cursorMonth-1,1);
    const lead=(first.getDay()+6)%7; // Monday first
    const days=new Date(cursorYear,cursorMonth,0).getDate();
    const cells=[];
    for(let i=0;i<lead;i++)cells.push('<div class="cal-day cal-blank" aria-hidden="true"></div>');
    for(let d=1;d<=days;d++){
      const date=`${cursorYear}-${pad(cursorMonth)}-${pad(d)}`;
      const classes=['cal-day'];
      if(date===today())classes.push('is-today');
      if(date===selectedDate)classes.push('is-selected');
      if(hasData(date))classes.push('has-data');
      cells.push(`<button type="button" class="${classes.join(' ')}" onclick="window.selectFitnessDate('${date}')" aria-label="${html(dayLabel(date))}">
        <span class="cal-date-number">${d}</span>
        <span class="cal-signals">${daySignals(date)}</span>
      </button>`);
    }
    return cells.join('');
  }

  function setText(exercise){
    const entries=Array.isArray(exercise?.setEntries)?exercise.setEntries.filter(s=>num(s.weight)||num(s.reps)||num(s.rpe)):[];
    if(entries.length){
      return entries.map((s,i)=>`<span>第${i+1}组 <strong>${round(s.weight,1)}kg × ${round(s.reps)}</strong>${num(s.rpe)?` <em>RPE ${round(s.rpe,1)}</em>`:''}</span>`).join('');
    }
    if(exercise?.weight||exercise?.reps)return `<span><strong>${round(exercise.weight,1)}kg × ${html(exercise.reps||'-')}</strong></span>`;
    return '<span class="cal-muted">未记录组数</span>';
  }

  function workoutCards(dateData){
    const manual=dateData.workouts.map(w=>`<article class="day-workout-card">
      <div class="day-card-head"><div><span class="day-icon">🏋</span><strong>${html(w.split||w.name||'力量训练')}</strong></div><span class="day-meta">${num(w.minutes)?`${round(w.minutes)} 分钟`:''}${num(w.calories)?` · ${round(w.calories)} kcal`:''}</span></div>
      ${(w.exercises||[]).length?`<div class="day-exercises">${w.exercises.map(e=>`<div class="day-exercise"><div class="day-exercise-name">${html(e.name||'动作')}</div><div class="day-sets">${setText(e)}</div></div>`).join('')}</div>`:'<div class="cal-muted">这次训练没有动作明细</div>'}
    </article>`).join('');

    const badminton=dateData.badminton.map(b=>`<article class="day-simple-card"><div><span class="day-icon">🏸</span><strong>羽毛球</strong><small>${b.source==='iphone-archive'?'历史记录':'手动记录'}</small></div><span>${num(b.minutes)?`${round(b.minutes)} 分钟`:''}${num(b.calories)?` · ${round(b.calories)} kcal`:''}</span></article>`).join('');

    const watch=dateData.healthWorkouts.map(w=>`<article class="day-simple-card"><div><span class="day-icon">⌚</span><strong>${html(w.name||'Apple Watch 锻炼')}</strong><small>${w.heartRateAvg!=null?`平均心率 ${round(w.heartRateAvg)} bpm`:'Apple Health'}</small></div><span>${num(w.minutes)?`${round(w.minutes)} 分钟`:''}${num(w.calories)?` · ${round(w.calories)} kcal`:''}</span></article>`).join('');

    return manual+badminton+watch||'<div class="calendar-empty">这一天没有运动记录</div>';
  }

  function mealCards(meals){
    if(!meals.length)return '<div class="calendar-empty">这一天没有饮食记录</div>';
    return meals.map((m,i)=>`<article class="day-meal-card">
      <div class="day-card-head"><div><span class="meal-index">${i+1}</span><strong>${html(m.name||'一餐')}</strong></div><span class="day-meta">${round(m.calories)} kcal</span></div>
      <div class="day-meal-macros"><span>P ${round(m.protein)}g</span><span>C ${round(m.carbs)}g</span><span>F ${round(m.fat)}g</span></div>
      ${Array.isArray(m.items)&&m.items.length?`<div class="day-food-items">${m.items.map(item=>`<div><span>${html(item.name||'食物')}${num(item.grams)?` · ${round(item.grams)}g`:''}</span><span>${round(item.calories)} kcal</span></div>`).join('')}</div>`:''}
    </article>`).join('');
  }

  function todayActions(){
    if(selectedDate!==today())return '';
    const next=typeof nextSplit==='function'?nextSplit():'胸';
    return `<section class="calendar-actions">
      <div class="calendar-actions-main">
        <button type="button" class="calendar-photo-action" onclick="openMeal()"><span>📷</span><div><strong>拍照记录饮食</strong><small>AI 自动拆分食物和营养</small></div></button>
        <button type="button" class="calendar-quick-action" onclick="openBad()"><span>🏸</span><div><strong>记录羽毛球</strong><small>时长与活动消耗</small></div></button>
      </div>
      <div class="calendar-split-actions"><span>开始力量训练</span>${['胸','肩','背','腿'].map(s=>`<button type="button" class="${s===next?'recommended':''}" onclick="openWorkout('${s}')">${s}${s===next?' · 建议':''}</button>`).join('')}</div>
    </section>`;
  }

  function selectedDayPanel(){
    const x=listFor(selectedDate);
    const t=mealTotals(x.meals);
    const sleepHours=x.health?.sleepHours??x.sleep?.hours;
    const manualMinutes=x.workouts.reduce((s,w)=>s+num(w.minutes),0)+x.badminton.reduce((s,b)=>s+num(b.minutes),0);
    return `<section class="calendar-day-detail">
      <div class="calendar-detail-head"><div><div class="hero-kicker">DAY REVIEW</div><h2>${html(dayLabel(selectedDate))}</h2><span>${selectedDate}</span></div>${selectedDate===today()?'<span class="today-badge">今天</span>':''}</div>
      <div class="calendar-summary-strip">
        <div><strong>${round(t.calories)}</strong><span>kcal</span></div>
        <div><strong>${round(t.protein)}g</strong><span>蛋白质</span></div>
        <div><strong>${round(manualMinutes)}</strong><span>运动分钟</span></div>
        <div><strong>${x.weight?`${round(x.weight.kg,1)}kg`:sleepHours!=null?`${round(sleepHours,1)}h`:'--'}</strong><span>${x.weight?'体重':sleepHours!=null?'睡眠':'身体数据'}</span></div>
      </div>
      ${todayActions()}
      <div class="calendar-detail-grid">
        <section class="calendar-detail-section"><div class="calendar-section-title"><span>运动</span><small>${x.workouts.length+x.badminton.length+x.healthWorkouts.length} 条记录</small></div>${workoutCards(x)}</section>
        <section class="calendar-detail-section"><div class="calendar-section-title"><span>饮食</span><small>${x.meals.length} 餐</small></div>${mealCards(x.meals)}</section>
      </div>
    </section>`;
  }

  function page(){
    return `<div class="calendar-page">
      <section class="calendar-shell-card">
        <div class="calendar-toolbar">
          <div><div class="hero-kicker">FITNESS CALENDAR</div><h2>${monthTitle(cursorYear,cursorMonth)}</h2><p>点任意一天，直接查看当天训练、羽毛球、饮食和身体数据。</p></div>
          <div class="calendar-nav"><button type="button" onclick="window.moveFitnessMonth(-1)" aria-label="上个月">‹</button><button type="button" class="today-jump" onclick="window.jumpFitnessToday()">今天</button><button type="button" onclick="window.moveFitnessMonth(1)" aria-label="下个月">›</button></div>
        </div>
        <div class="calendar-weekdays"><span>一</span><span>二</span><span>三</span><span>四</span><span>五</span><span>六</span><span>日</span></div>
        <div class="calendar-grid">${calendarGrid()}</div>
        <div class="calendar-legend"><span><i class="dot strength"></i>力量</span><span><i class="dot badminton"></i>羽毛球</span><span><i class="dot meal"></i>饮食</span><span><i class="dot watch"></i>Watch</span></div>
      </section>
      ${selectedDayPanel()}
    </div>`;
  }

  window.selectFitnessDate=function(date){
    selectedDate=date;
    const {y,m}=dateParts(date);cursorYear=y;cursorMonth=m;
    if(typeof render==='function')render();
  };
  window.moveFitnessMonth=function(delta){
    let m=cursorMonth+delta,y=cursorYear;
    if(m<1){m=12;y--;}if(m>12){m=1;y++;}
    cursorYear=y;cursorMonth=m;
    const max=new Date(y,m,0).getDate();
    const currentDay=Math.min(dateParts(selectedDate).d||1,max);
    selectedDate=`${y}-${pad(m)}-${pad(currentDay)}`;
    if(typeof render==='function')render();
  };
  window.jumpFitnessToday=function(){
    selectedDate=today();const {y,m}=dateParts(selectedDate);cursorYear=y;cursorMonth=m;
    if(typeof render==='function')render();
  };

  window.training=function calendarTraining(){return page();};
  if(typeof render==='function')render();
})();
