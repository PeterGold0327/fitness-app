/* One-time migration helper for the existing iPhone Growth Timeline export.
   Import the archive.md file from the ZIP exported by the iPhone app.
   The importer only ADDS missing records. It never deletes Windows records. */
(function(){
  function num(s){const m=String(s||'').match(/-?\d+(?:\.\d+)?/);return m?Number(m[0]):null;}
  function uniq(list,id){const out=[],seen=new Set();for(const x of list){const k=id(x);if(!seen.has(k)){seen.add(k);out.push(x);}}return out;}
  function isGymSection(section){return /gym|健身|力量训练|训练记录|strength/i.test(section||'');}
  function isBadmintonSection(section){return /badminton|羽毛球/i.test(section||'');}
  function isNoneLogged(line){return /none logged|not logged|未记录|无记录|暂无/i.test(line||'');}

  function inferSplit(workout){
    const text=[workout?.name,...(workout?.exercises||[]).map(x=>x.name)].join(' ').toLowerCase();
    if(/胸|卧推|胸推|飞鸟|夹胸|chest|bench/.test(text))return'胸';
    if(/肩|侧平举|肩推|推举|delt|shoulder/.test(text))return'肩';
    if(/背|划船|下拉|引体|背阔|row|pulldown|pull-up|back/.test(text))return'背';
    if(/腿|深蹲|腿举|哈克|硬拉|分腿蹲|腿弯举|leg|squat|deadlift|lower/.test(text))return'腿';
    return workout?.split||workout?.name||'健身';
  }

  function parseExerciseLine(line){
    const text=String(line||'').replace(/^[-•]\s*/,'').trim();
    let m=text.match(/([\d.]+)\s*kg\s*[×x]\s*(\d+)\s*reps?\s*[×x]\s*(\d+)\s*sets?(?:\s*·?\s*RPE\s*([\d.]+))?/i);
    if(m)return{weight:Number(m[1]),reps:Number(m[2]),sets:Number(m[3]),rpe:Number(m[4]||0)};
    m=text.match(/([\d.]+)\s*(?:千克|公斤|kg)\s*[×x]\s*(\d+)\s*次\s*[×x]\s*(\d+)\s*组(?:\s*·?\s*RPE\s*([\d.]+))?/i);
    if(m)return{weight:Number(m[1]),reps:Number(m[2]),sets:Number(m[3]),rpe:Number(m[4]||0)};
    const nums=[...text.matchAll(/-?\d+(?:\.\d+)?/g)].map(x=>Number(x[0]));
    if(nums.length>=3&&(text.includes('RPE')||/组|sets?/i.test(text))){
      return{weight:nums[0],reps:Math.round(nums[1]),sets:Math.round(nums[2]),rpe:Number(nums[3]||0)};
    }
    return null;
  }

  function parseArchive(text){
    const lines=text.replace(/\r/g,'').split('\n');
    const imported={meals:[],workouts:[],badminton:[],weights:[],sleep:[]};
    let day=null,section='',meal=null,workout=null,exercise=null;

    const flushMeal=()=>{if(meal&&day){imported.meals.push(meal);}meal=null;};
    const flushWorkout=()=>{
      if(workout&&day){workout.split=inferSplit(workout);imported.workouts.push(workout);}
      workout=null;exercise=null;
    };

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
      if(isGymSection(section)){
        if(line.startsWith('### ')){
          flushWorkout();
          const title=line.slice(4).trim()||'健身';
          workout={id:crypto.randomUUID(),date:day,split:title,name:title,minutes:0,calories:0,exercises:[],source:'iphone-archive'};
          continue;
        }
        if(workout&&line.startsWith('#### ')){
          exercise={name:line.slice(5).trim(),weight:0,reps:'',sets:0,rpe:0};
          workout.exercises.push(exercise);
          continue;
        }
        if(exercise&&line.startsWith('- ')){
          const parsed=parseExerciseLine(line);
          if(parsed){exercise.weight=parsed.weight;exercise.reps=String(parsed.reps);exercise.sets=parsed.sets;exercise.rpe=parsed.rpe;}
          continue;
        }
      }
      if(isBadmintonSection(section)){
        if(line&&!isNoneLogged(line)&&(/logged|已记录|有记录|羽毛球/i.test(line))){
          imported.badminton.push({id:crypto.randomUUID(),date:day,minutes:0,calories:0,source:'iphone-archive'});
        }
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
    modal(`<h2>重新导入 iPhone 历史记录</h2>
      <div class="surface-note">选择之前导出的 ZIP 里的 <strong>archive.md</strong>。新版导入器已经兼容中文健身格式（千克 / 次 / 组 / RPE）、羽毛球记录，并会把旧训练自动归到胸 / 肩 / 背 / 腿，方便后续读取上次动作表现。</div>
      <div class="field"><label>选择 archive.md</label><input id="iphoneArchiveFile" type="file" accept=".md,text/markdown,text/plain"></div>
      <button type="button" class="primary" onclick="importIPhoneArchive()">导入并合并</button>
      <div class="surface-note">重复导入会自动去重，不会覆盖你现在 Windows 上的新记录。</div>`);
  };

  window.importIPhoneArchive=async function(){
    const file=document.querySelector('#iphoneArchiveFile')?.files?.[0];
    if(!file){alert('请先选择 archive.md');return;}
    try{
      const data=parseArchive(await file.text());
      mergeImported(data);
      closeModal();
      alert(`导入完成：饮食 ${data.meals.length}，健身 ${data.workouts.length}，羽毛球 ${data.badminton.length}，体重 ${data.weights.length}，睡眠 ${data.sleep.length}。重复记录已自动去重。`);
    }catch(e){console.error(e);alert('导入失败：请确认选择的是 iPhone 成长档案里的 archive.md');}
  };

  function mountImport(){
    const top=document.querySelector('.topbar');if(!top||document.querySelector('#iphoneImportChip'))return;
    const btn=document.createElement('button');btn.id='iphoneImportChip';btn.className='cloud-chip import-chip';btn.type='button';btn.innerHTML='<span>⇩</span><span>导入 iPhone</span>';btn.onclick=window.openIPhoneImport;
    const cloud=document.querySelector('.cloud-actions');if(cloud)cloud.appendChild(btn);else top.insertBefore(btn,document.querySelector('#quickAdd'));
  }
  window.addEventListener('DOMContentLoaded',mountImport);
})();
