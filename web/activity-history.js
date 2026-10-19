/* Add visible training history to the Windows training page. */
(function(){
  function historyHtml(){
    const workouts=(state.workouts||[]).map(x=>({type:'gym',date:x.date||'',item:x}));
    const badminton=(state.badminton||[]).map(x=>({type:'badminton',date:x.date||'',item:x}));
    const recent=[...workouts,...badminton]
      .filter(x=>x.date)
      .sort((a,b)=>b.date.localeCompare(a.date))
      .slice(0,16);
    if(!recent.length){
      return `<section class="card"><div class="section-title">历史运动</div><div class="empty">还没有历史运动记录</div></section>`;
    }
    return `<section class="card">
      <div class="section-head"><div class="section-title">历史运动</div><span class="subtle">最近 ${recent.length} 条</span></div>
      <div class="activity-history-list">${recent.map(row=>{
        if(row.type==='badminton'){
          const m=Number(row.item.minutes)||0,c=Number(row.item.calories)||0;
          const detail=m?`${m} 分钟${c?` · ${Math.round(c)} kcal`:''}`:(row.item.source==='iphone-archive'?'iPhone 历史记录':'已记录');
          return `<div class="timeline-item"><div class="timeline-date">${esc(row.date.slice(5))}</div><div><strong>🏸 羽毛球</strong><div class="tiny">${detail}</div></div></div>`;
        }
        const w=row.item, exercises=w.exercises||[];
        const names=exercises.slice(0,4).map(e=>e.name).filter(Boolean).join(' · ');
        const detail=[w.minutes?`${w.minutes} 分钟`:'',names||`${exercises.length} 个动作`].filter(Boolean).join(' · ');
        return `<div class="timeline-item"><div class="timeline-date">${esc(row.date.slice(5))}</div><div><strong>🏋 ${esc(w.split||w.name||'健身')}</strong><div class="tiny">${esc(detail||'训练记录')}</div></div></div>`;
      }).join('')}</div>
    </section>`;
  }

  const original=window.training;
  if(typeof original==='function'){
    window.training=function trainingWithHistory(){
      const html=original();
      return html.replace('</div>',`${historyHtml()}</div>`);
    };
  }

  if(typeof render==='function')render();
})();
