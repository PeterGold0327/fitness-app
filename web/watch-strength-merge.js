/* Treat Apple Watch Functional Strength Training as the same gym session, not a separate workout. */
(function(){
  function pendingStrength(date){
    return (state.workouts||[]).find(w=>w?.date===date&&w?.source==='apple-health-strength'&&(!Array.isArray(w.exercises)||!w.exercises.length))||null;
  }

  function copyWatchMetrics(target,watch){
    if(!target||!watch)return;
    const fields=['watchWorkoutId','watchStart','watchEnd','watchHeartRateAvg','watchHeartRateMin','watchHeartRateMax','metricsSource'];
    fields.forEach(k=>{if(watch[k]!==undefined)target[k]=watch[k];});
    if(Number.isFinite(Number(watch.minutes)))target.minutes=Number(watch.minutes);
    if(Number.isFinite(Number(watch.calories)))target.calories=Number(watch.calories);
  }

  const originalOpenWorkout=window.openWorkout;
  if(typeof originalOpenWorkout==='function'){
    window.openWorkout=function openWorkoutWithWatch(split){
      originalOpenWorkout(split);
      const watch=pendingStrength(key());
      if(!watch)return;
      const minutes=document.querySelector('#gymMinutes');
      const calories=document.querySelector('#gymCalories');
      if(minutes){minutes.value=Number(watch.minutes)||0;minutes.readOnly=true;}
      if(calories){calories.value=Number(watch.calories)||0;calories.readOnly=true;}
      const card=document.querySelector('.workout-session-card');
      if(card&&!card.querySelector('.watch-auto-note')){
        const note=document.createElement('div');
        note.className='surface-note watch-auto-note';
        note.innerHTML=`⌚ Apple Watch 已自动记录本次健身：<strong>${Math.round(Number(watch.minutes)||0)} 分钟</strong> · <strong>${Math.round(Number(watch.calories)||0)} kcal</strong>。这里只需要补动作、重量、次数和 RPE。`;
        const grid=card.querySelector('.grid2');
        if(grid)card.insertBefore(note,grid);
      }
    };
  }

  const originalSaveWorkout=window.saveWorkout;
  if(typeof originalSaveWorkout==='function'){
    window.saveWorkout=function saveWorkoutWithWatch(split){
      const date=key();
      const watch=pendingStrength(date);
      const before=new Set((state.workouts||[]).map(w=>w.id));
      originalSaveWorkout(split);
      if(!watch)return;
      const created=[...(state.workouts||[])].reverse().find(w=>w?.date===date&&w?.split===split&&!before.has(w.id));
      if(!created)return;
      copyWatchMetrics(created,watch);
      created.source='manual-web';
      state.workouts=(state.workouts||[]).filter(w=>w.id!==watch.id);
      save();
    };
  }
})();
