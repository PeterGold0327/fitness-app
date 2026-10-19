/* One-time migration helper for the existing iPhone Growth Timeline export.
   Import the archive.md file from the ZIP exported by the iPhone app.
   The importer only ADDS missing records. It never deletes Windows records. */
(function(){
  function num(s){const m=String(s||'').match(/-?\d+(?:\.\d+)?/);return m?Number(m[0]):null;}
  function uniq(list,id){const out=[],seen=new Set();for(const x of list){const k=id(x);if(!seen.has(k)){seen.add(k);out.push(x);}}return out;}

  function parseArchive(text){
    const lines=text.replace(/\r/g,'').split('\n');
    const imported={meals:[],workouts:[],badminton:[],weights:[],sleep:[]};
    let day=null,section='',meal=null,workout=null,exercise=null;

    const flushMeal=()=>{if(meal&&day){imported.meals.push(meal);}meal=null;};
    const flushWorkout=()=>{if(workout&&day){imported.workouts.push(workout);}workout=null;exercise=null;};

    for(let i=0;i<lines.length;i++){
      const raw=lines[i],line=raw.trim();
      const dateMatch=line.match(/^# (\d{4}-\d{2}-\d{2})$/);
      if(dateMatch){flushMeal();flushWorkout();day=dateMatch[1];section='';continue;}
      if(!day)continue;

      if(line.startsWith('## ')){flushMeal();flushWorkout();section=line.slice(3).trim().toLowerCase();continue;}

      if(section.includes('body')||section.includes('身体')){
        if(/Weight:|体重/.test(line)){const v=num(line);if(v)imported.weights.push({date:day,kg:v,source:'iphone-archive'});}continue;
      }
      if(section.includes('sleep')||section.includes('睡眠')){
        if(/\d/.test(line)){const v=num(line);if(v!=null)imported.sleep.push({date:day,hours:v,source:'iphone-archive'});}continue;
      }
      if(section.includes('nutrition')||section.includes('营养')){
        if(line.startsWith('### ')){
          flushMeal();
          const title=line.slice(4).trim();
          const name=title.includes(':')?title.split(':').slice(1).join(':').trim():title;
          meal={id:crypto.randomUUID(),date:day,name:name||'iPhone 饮食记录',calories:0,protein:0,carbs:0,fat:0,source:'iphone-archive'};
          continue;
        }
        if(meal&&(line.includes('Calories:')||line.includes('热量:')||line.includes('热量：'))){
          const nums=[...line.matchAll(/-?\d+(?:\.\d+)?/g)].map(x=>Number(x[0]));
          if(nums.length>=4){meal.calories=nums[0];meal.protein=nums[1];meal.carbs=nums[2];meal.fat=nums[3];}
          continue;
        }
      }
      if(section.includes('gym')||section.includes('健身')){
        if(line.startsWith('### ')){flushWorkout();workout={id:crypto.randomUUID(),date:day,split:line.slice(4).trim()||'健身',name:line.slice(4).trim()||'健身',minutes:0,calories:0,exercises:[],source:'iphone-archive'};continue;}
        if(workout&&line.startsWith('#### ')){exercise={name:line.slice(5).trim(),weight:0,reps:'',sets:0,rpe:0};workout.exercises.push(exercise);continue;}
        if(exercise&&line.startsWith('- ')){
          const m=line.match(/([\d.]+)\s*kg\s*[×x]\s*(\d+)\s*reps\s*[×x]\s*(\d+)\s*sets(?:\s*·\s*RPE\s*([\d.]+))?/i);
          if(m){exercise.weight=Number(m[1]);exercise.reps=m[2];exercise.sets=Number(m[3]);exercise.rpe=Number(m[4]||0);}continue;
        }
      }
      if(section.includes('badminton')||section.includes('羽毛球')){
        if(/logged|已记录|有记录/i.test(line)&&!/none|未记录/i.test(line))imported.badminton.push({id:crypto.randomUUID(),date:day,minutes:0,calories:0,source:'iphone-archive'});
      }
    }
    flushMeal();flushWorkout();
    return imported;
  }

  function mergeImported(data){
    state.meals=uniq([...(state.meals||[]),...data.meals],x=>`${x.date}|${x.name}|${x.calories}|${x.protein}|${x.carbs}|${x.fat}`);
    state.workouts=uniq([...(state.workouts||[]),...data.workouts],x=>`${x.date}|${x.split||x.name}|${(x.exercises||[]).map(e=>e.name).join(',')}`);
    state.badminton=uniq([...(state.badminton||[]),...data.badminton],x=>`${x.date}|${x.source||''}`);
    state.weights=uniq([...(state.weights||[]),...data.weights],x=>x.date);
    state.sleep=uniq([...(state.sleep||[]),...data.sleep],x=>x.date);
    save();
  }

  window.openIPhoneImport=function(){
    modal(`<h2>导入之前 iPhone App 的记录</h2>
      <div class="surface-note">在 iPhone App 的“成长时间线 → 导出成长档案”导出 ZIP。把 ZIP 解压后，选择里面的 <strong>archive.md</strong>。这里会把饮食、体重、睡眠、健身和羽毛球历史合并到 Windows；不会删除任何现有 Windows 数据。</div>
      <div class="field"><label>选择 archive.md</label><input id="iphoneArchiveFile" type="file" accept=".md,text/markdown,text/plain"></div>
      <button type="button" class="primary" onclick="importIPhoneArchive()">导入并合并</button>
      <div class="surface-note">照片仍保留在原导出 ZIP 里；等云端照片存储接好后再统一上传，不会要求你重新拍。</div>`);
  };

  window.importIPhoneArchive=async function(){
    const file=document.querySelector('#iphoneArchiveFile')?.files?.[0];
    if(!file){alert('请先选择 archive.md');return;}
    try{
      const data=parseArchive(await file.text());
      mergeImported(data);
      closeModal();
      const count=data.meals.length+data.workouts.length+data.badminton.length+data.weights.length+data.sleep.length;
      alert(`导入完成：合并了 ${count} 条历史记录。原 Windows 数据没有被删除。`);
    }catch(e){console.error(e);alert('导入失败：请确认选择的是 iPhone 成长档案里的 archive.md');}
  };

  function mountImport(){
    const top=document.querySelector('.topbar');if(!top||document.querySelector('#iphoneImportChip'))return;
    const btn=document.createElement('button');btn.id='iphoneImportChip';btn.className='cloud-chip import-chip';btn.type='button';btn.innerHTML='<span>⇩</span><span>导入 iPhone</span>';btn.onclick=window.openIPhoneImport;
    const cloud=document.querySelector('.cloud-actions');if(cloud)cloud.appendChild(btn);else top.insertBefore(btn,document.querySelector('#quickAdd'));
  }
  window.addEventListener('DOMContentLoaded',mountImport);
})();
