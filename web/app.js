const STORAGE_KEY = 'duoduo-fitness-web-v1';

const defaultState = {
  profile: { name:'多多', calorieTarget:2700, proteinTarget:130, fatTarget:70, weightGoal:null },
  meals: [],
  workouts: [],
  badminton: [],
  weights: [],
  sleep: [],
  templates: {
    胸:['卧推','上斜哑铃卧推','夹胸 / 飞鸟','器械胸推','爆发俯卧撑'],
    肩:['肩推','侧平举','绳索侧平举','反向飞鸟','旋转核心'],
    背:['高位下拉 / 引体','坐姿划船','胸托划船','直臂下压','Pallof Press'],
    腿:['深蹲 / 哈克 / 腿举','罗马尼亚硬拉','保加利亚分腿蹲','腿弯举','小腿提踵','侧向跨步跳']
  }
};

let state = loadState();
let currentTab = 'home';

function loadState(){
  try { return { ...structuredClone(defaultState), ...JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') }; }
  catch { return structuredClone(defaultState); }
}
function saveState(){ localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); render(); }
function todayKey(d=new Date()){ return d.toISOString().slice(0,10); }
function fmtDate(d=new Date()){ return d.toLocaleDateString('zh-CN',{year:'numeric',month:'long',day:'numeric',weekday:'long'}); }
function sum(list,key){ return list.reduce((a,x)=>a+(Number(x[key])||0),0); }
function clampPct(v,max){ return Math.max(0,Math.min(100,max ? (v/max)*100 : 0)); }
function todayMeals(){ const k=todayKey(); return state.meals.filter(x=>x.date===k); }
function todayWorkouts(){ const k=todayKey(); return state.workouts.filter(x=>x.date===k); }
function todayBadminton(){ const k=todayKey(); return state.badminton.filter(x=>x.date===k); }
function yesterdayKey(){ const d=new Date(); d.setDate(d.getDate()-1); return todayKey(d); }
function latestSleep(){ return [...state.sleep].sort((a,b)=>b.date.localeCompare(a.date))[0]; }
function latestWeight(){ return [...state.weights].sort((a,b)=>b.date.localeCompare(a.date))[0]; }

function updateGreeting(){
  const h=new Date().getHours();
  document.querySelector('#greeting').textContent = `${h<12?'早上好':h<18?'下午好':'晚上好'}，${state.profile.name||'多多'}`;
  document.querySelector('#todayDate').textContent = fmtDate();
}

function coachAdvice(){
  const meals=todayMeals(); const kcal=sum(meals,'calories'); const protein=sum(meals,'protein');
  const badminton=todayBadminton(); const active=sum(badminton,'calories')+sum(todayWorkouts(),'calories');
  const remainK=Math.max(0,state.profile.calorieTarget-kcal); const remainP=Math.max(0,state.profile.proteinTarget-protein);
  if (active>=700) return `今天运动量明显高于平时。下一餐优先补碳水和蛋白质；不需要机械补回全部 ${Math.round(active)} kcal。`;
  if (remainP>=35) return `今天蛋白质还差约 ${Math.round(remainP)}g，下一餐优先安排高蛋白食物。`;
  if (remainK<=300 && meals.length) return '今天热量已经接近目标，晚餐保持正常份量即可。';
  const next = nextSplit();
  if (next) return `今天如果健身，建议继续 ${next} 循环。打开训练页会自动带出上一次同动作表现。`;
  return '今天先正常记录饮食和训练。数据积累后，建议会越来越具体。';
}
function nextSplit(){
  const order=['胸','肩','背','腿'];
  const history=[...state.workouts].filter(x=>order.includes(x.split)).sort((a,b)=>b.date.localeCompare(a.date));
  if(!history.length) return '胸';
  const i=order.indexOf(history[0].split); return order[(i+1)%order.length];
}

function homeView(){
  const meals=todayMeals(), kcal=sum(meals,'calories'), p=sum(meals,'protein');
  const y=state.meals.filter(x=>x.date===yesterdayKey());
  const yBad=state.badminton.filter(x=>x.date===yesterdayKey());
  const yGym=state.workouts.filter(x=>x.date===yesterdayKey());
  const sleep=latestSleep();
  return `
    <section class="card hero-card"><div class="hero-title">✦ 今日建议</div><div class="hero-copy">${coachAdvice()}</div></section>
    <button class="primary" onclick="openMealModal()">📷 拍照后记录饮食</button>
    <div class="section"><div class="grid2">
      <button class="secondary" onclick="setTab('training')">🏋 开始训练</button>
      <button class="secondary" onclick="openAdvice()">查看今日建议</button>
    </div></div>
    <section class="card"><div class="section-title">今日目标</div>
      <div class="row"><div><div class="row-title">热量</div><div class="row-sub">${Math.round(kcal)} / ${state.profile.calorieTarget} kcal</div></div><div>${Math.round(clampPct(kcal,state.profile.calorieTarget))}%</div></div>
      <div class="progress"><span style="width:${clampPct(kcal,state.profile.calorieTarget)}%"></span></div>
      <div class="row"><div><div class="row-title">蛋白质</div><div class="row-sub">${Math.round(p)} / ${state.profile.proteinTarget} g</div></div><div>${Math.round(clampPct(p,state.profile.proteinTarget))}%</div></div>
      <div class="progress"><span style="width:${clampPct(p,state.profile.proteinTarget)}%"></span></div>
    </section>
    <section class="card"><div class="section-title">昨日完成</div>
      <div class="row"><span>饮食</span><span>${y.length?`${Math.round(sum(y,'calories'))} kcal`:'未记录'}</span></div>
      <div class="row"><span>力量训练</span><span>${yGym.length?`${yGym.length} 次`:'未记录'}</span></div>
      <div class="row"><span>羽毛球</span><span>${yBad.length?`${Math.round(sum(yBad,'minutes'))} 分钟`:'未记录'}</span></div>
      <div class="row"><span>活动消耗</span><span>${Math.round(sum(yBad,'calories')+sum(yGym,'calories'))} kcal</span></div>
    </section>
    <section class="card"><div class="section-title">☾ 睡眠</div>${sleep?`<div class="hero-title">${Number(sleep.hours).toFixed(1)} 小时</div><div class="muted">${sleep.hours>=8?'充足':sleep.hours>=7?'正常':'偏少'}</div>`:'<div class="empty">还没有睡眠数据。Web 版可手动导入；Apple Health 仍需 iPhone App 读取。</div>'}</section>
  `;
}

function nutritionView(){
  const meals=todayMeals(), kcal=sum(meals,'calories'), p=sum(meals,'protein');
  return `<section class="card"><div class="section-title">今日营养</div><div class="grid3">
    <div class="metric"><div class="value">${Math.round(kcal)}</div><div class="label">/ ${state.profile.calorieTarget} kcal</div></div>
    <div class="metric"><div class="value">${Math.round(p)}g</div><div class="label">/ ${state.profile.proteinTarget}g 蛋白质</div></div>
    <div class="metric"><div class="value">${meals.length}</div><div class="label">餐已记录</div></div>
  </div></section>
  <button class="primary" onclick="openMealModal()">＋ 记录这一餐</button>
  <div class="section"><div class="section-title">今天吃了什么</div><section class="card">${meals.length?meals.map(m=>`<div class="row"><div><div class="row-title">${esc(m.name)}</div><div class="row-sub">${Math.round(m.calories)} kcal · 蛋白质 ${Math.round(m.protein)}g</div></div><button class="secondary" onclick="deleteMeal('${m.id}')">删除</button></div>`).join(''):'<div class="empty">还没有饮食记录</div>'}</section></div>`;
}

function trainingView(){
  const todayGym=todayWorkouts(), bad=todayBadminton();
  return `<section class="card"><div class="section-title">今日运动</div>
    <div class="row"><div><div class="row-title">羽毛球</div><div class="row-sub">${bad.length?`${Math.round(sum(bad,'minutes'))} 分钟 · ${Math.round(sum(bad,'calories'))} kcal`:'今天尚未记录'}</div></div><button class="secondary" onclick="openBadmintonModal()">${bad.length?'补记':'记录'}</button></div>
    <div class="row"><div><div class="row-title">健身</div><div class="row-sub">${todayGym.length?`${Math.round(sum(todayGym,'minutes'))} 分钟 · ${Math.round(sum(todayGym,'calories'))} kcal`:'今天尚未记录'}</div></div></div>
  </section>
  <div class="section"><div class="section-title">胸 / 肩 / 背 / 腿</div><div class="grid2">${['胸','肩','背','腿'].map(s=>`<button class="secondary" onclick="openWorkout('${s}')">${s}训练</button>`).join('')}</div></div>`;
}

function findPrevious(exerciseName, split){
  const sessions=[...state.workouts].filter(x=>x.split===split).sort((a,b)=>b.date.localeCompare(a.date));
  for(const s of sessions){ const e=(s.exercises||[]).find(x=>x.name===exerciseName); if(e) return {date:s.date,...e}; }
  return null;
}
function progressSuggestion(prev){
  if(!prev) return '第一次记录，选择一个能稳定完成的起始重量。';
  return `先从上次 ${prev.weight}kg 的表现开始；如果今天完成更轻松，下次再小幅加重。`;
}
function openWorkout(split){
  const exercises=state.templates[split]||[];
  const rows=exercises.map((name,i)=>{const p=findPrevious(name,split);return `<div class="exercise"><div class="exercise-name">${esc(name)}</div><div class="previous">${p?`上次 ${p.date}：${p.weight}kg × ${p.reps||'-'}${p.sets?` · ${p.sets}组`:''}`:'暂无上次记录'}</div><div class="suggestion">${progressSuggestion(p)}</div><div class="grid2"><div class="field"><label>重量 kg</label><input id="w${i}" type="number" step="0.5" value="${p?.weight||''}"></div><div class="field"><label>次数（可写 10/9/8）</label><input id="r${i}" value="${p?.reps||''}"></div></div></div>`}).join('');
  modal(`<h2>${split}训练</h2>${rows}<div class="grid2"><div class="field"><label>时长（分钟）</label><input id="gymMinutes" type="number" value="75"></div><div class="field"><label>活动消耗 kcal</label><input id="gymCalories" type="number" value="0"></div></div><button type="button" class="primary" onclick="saveWorkout('${split}')">保存本次训练</button>`);
}
function saveWorkout(split){
  const exercises=(state.templates[split]||[]).map((name,i)=>({name,weight:Number(document.querySelector(`#w${i}`).value)||0,reps:document.querySelector(`#r${i}`).value.trim(),sets:(document.querySelector(`#r${i}`).value.match(/\//g)||[]).length+1})).filter(x=>x.weight||x.reps);
  state.workouts.push({id:crypto.randomUUID(),date:todayKey(),split,minutes:Number(document.querySelector('#gymMinutes').value)||0,calories:Number(document.querySelector('#gymCalories').value)||0,exercises});
  closeModal(); saveState();
}

function progressView(){
  const weights=[...state.weights].sort((a,b)=>b.date.localeCompare(a.date));
  const workouts=[...state.workouts].sort((a,b)=>b.date.localeCompare(a.date)).slice(0,8);
  return `<section class="card"><div class="section-title">成长时间线</div><div class="muted">Web 版先读取和保存浏览器数据；以后接云端后可与 iPhone 共用同一份历史。</div></section>
  <section class="card"><div class="section-title">体重历史</div>${weights.length?weights.slice(0,10).map(x=>`<div class="row"><span>${x.date}</span><strong>${x.kg} kg</strong></div>`).join(''):'<div class="empty">暂无体重记录</div>'}<button class="secondary" onclick="openWeightModal()">记录体重</button></section>
  <section class="card"><div class="section-title">最近训练</div>${workouts.length?workouts.map(x=>`<div class="timeline-item"><div class="timeline-date">${x.date.slice(5)}</div><div><strong>${x.split||'健身'}</strong><div class="tiny">${x.minutes||0} 分钟 · ${(x.exercises||[]).length} 个动作</div></div></div>`).join(''):'<div class="empty">暂无训练记录</div>'}</section>`;
}

function settingsView(){
  return `<section class="card"><div class="section-title">个人目标</div>
    <div class="field"><label>称呼</label><input id="nameSetting" value="${esc(state.profile.name)}"></div>
    <div class="field"><label>每日热量 kcal</label><input id="calSetting" type="number" value="${state.profile.calorieTarget}"></div>
    <div class="field"><label>每日蛋白质 g</label><input id="proteinSetting" type="number" value="${state.profile.proteinTarget}"></div>
    <button class="primary" onclick="saveSettings()">保存设置</button>
  </section>
  <section class="card"><div class="section-title">数据与备份</div>
    <div class="list-actions"><button class="secondary" onclick="exportData()">导出 JSON</button><button class="secondary" onclick="document.querySelector('#importFile').click()">导入 JSON</button><input id="importFile" hidden type="file" accept="application/json" onchange="importData(this.files[0])"></div>
    <p class="muted">当前 Web MVP 数据存在这个浏览器的 localStorage。导出文件可作为 Windows 备份。真正与 iPhone 自动同步需要下一步接云端数据库。</p>
  </section>
  <section class="card"><div class="section-title">Apple Watch / Health</div><p class="muted">浏览器不能直接读取 Apple Health。Apple Watch 数据仍由 iPhone App 读取；以后接云同步后，iPhone 可把这些数据同步到 Web。</p></section>`;
}

function render(){ updateGreeting(); const app=document.querySelector('#app'); app.innerHTML = ({home:homeView,nutrition:nutritionView,training:trainingView,progress:progressView,settings:settingsView})[currentTab](); document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x.dataset.tab===currentTab)); }
function setTab(tab){ currentTab=tab; render(); }
window.setTab=setTab;

document.querySelectorAll('.tab').forEach(btn=>btn.onclick=()=>setTab(btn.dataset.tab));
document.querySelector('#quickAdd').onclick=()=>modal(`<h2>快速记录</h2><div class="grid2"><button type="button" class="secondary" onclick="closeModal();openMealModal()">记录饮食</button><button type="button" class="secondary" onclick="closeModal();openWeightModal()">记录体重</button><button type="button" class="secondary" onclick="closeModal();openBadmintonModal()">羽毛球</button><button type="button" class="secondary" onclick="closeModal();setTab('training')">健身</button></div>`);

function modal(html){ document.querySelector('#modalBody').innerHTML=html; document.querySelector('#modal').showModal(); }
function closeModal(){ document.querySelector('#modal').close(); }
window.closeModal=closeModal;
function openAdvice(){ modal(`<h2>今日建议</h2><p class="hero-copy">${coachAdvice()}</p>`); }
function openMealModal(){ modal(`<h2>记录饮食</h2><div class="field"><label>餐名</label><input id="mealName" placeholder="例如：牛肉饭"></div><div class="grid2"><div class="field"><label>热量 kcal</label><input id="mealCal" type="number"></div><div class="field"><label>蛋白质 g</label><input id="mealProtein" type="number"></div><div class="field"><label>碳水 g</label><input id="mealCarbs" type="number"></div><div class="field"><label>脂肪 g</label><input id="mealFat" type="number"></div></div><p class="muted">这个 Web MVP 先支持快速手动记录。iPhone 上的 B.ai 拍照识别逻辑不受影响；下一步可把同一识别服务接到 Web。</p><button type="button" class="primary" onclick="saveMeal()">保存</button>`); }
function saveMeal(){ state.meals.push({id:crypto.randomUUID(),date:todayKey(),name:document.querySelector('#mealName').value||'一餐',calories:Number(document.querySelector('#mealCal').value)||0,protein:Number(document.querySelector('#mealProtein').value)||0,carbs:Number(document.querySelector('#mealCarbs').value)||0,fat:Number(document.querySelector('#mealFat').value)||0}); closeModal(); saveState(); }
function deleteMeal(id){ state.meals=state.meals.filter(x=>x.id!==id); saveState(); }
function openWeightModal(){ modal(`<h2>记录体重</h2><div class="field"><label>体重 kg</label><input id="weightKg" type="number" step="0.1" value="${latestWeight()?.kg||''}"></div><button type="button" class="primary" onclick="saveWeight()">保存</button>`); }
function saveWeight(){ const kg=Number(document.querySelector('#weightKg').value); if(kg){ state.weights=state.weights.filter(x=>x.date!==todayKey()); state.weights.push({date:todayKey(),kg}); } closeModal(); saveState(); }
function openBadmintonModal(){ modal(`<h2>记录羽毛球</h2><div class="grid2"><div class="field"><label>时长（分钟）</label><input id="badMinutes" type="number"></div><div class="field"><label>活动消耗 kcal</label><input id="badCalories" type="number"></div></div><button type="button" class="primary" onclick="saveBadminton()">保存</button>`); }
function saveBadminton(){ state.badminton.push({id:crypto.randomUUID(),date:todayKey(),minutes:Number(document.querySelector('#badMinutes').value)||0,calories:Number(document.querySelector('#badCalories').value)||0}); closeModal(); saveState(); }
function saveSettings(){ state.profile.name=document.querySelector('#nameSetting').value||'多多'; state.profile.calorieTarget=Number(document.querySelector('#calSetting').value)||2700; state.profile.proteinTarget=Number(document.querySelector('#proteinSetting').value)||130; saveState(); }
function exportData(){ const blob=new Blob([JSON.stringify(state,null,2)],{type:'application/json'}); const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download=`duoduo-fitness-${todayKey()}.json`; a.click(); URL.revokeObjectURL(a.href); }
async function importData(file){ if(!file)return; try{ const data=JSON.parse(await file.text()); state={...structuredClone(defaultState),...data}; saveState(); alert('导入成功'); }catch{alert('导入失败：文件格式不正确');} }
function esc(s=''){ return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

Object.assign(window,{openMealModal,saveMeal,deleteMeal,openWeightModal,saveWeight,openBadmintonModal,saveBadminton,saveSettings,exportData,importData,openWorkout,saveWorkout,openAdvice});

if('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(()=>{});
render();
