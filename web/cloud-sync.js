/* Duoduo Fitness cloud sync.
   Uses Supabase Auth + one private JSON snapshot per user.
   Existing localStorage data remains the source of truth until the user signs in.
   First sign-in uploads local data when the cloud is empty, so current Windows records are preserved. */
(function(){
  const STORAGE_KEY='duoduo-fitness-web-v1';
  const cfg=window.DUODUO_CLOUD_CONFIG;
  const ready=cfg&&cfg.supabaseUrl&&cfg.supabaseAnonKey&&!cfg.supabaseUrl.includes('YOUR_PROJECT');
  let client=null,user=null,syncTimer=null,pulling=false;
  const originalSetItem=Storage.prototype.setItem;

  function status(text,tone='muted'){
    const el=document.querySelector('#cloudStatusText');
    if(el){el.textContent=text;el.dataset.tone=tone;}
  }
  function currentLocal(){try{return JSON.parse(localStorage.getItem(STORAGE_KEY)||'{}')}catch{return {}}}
  function sameData(a,b){try{return JSON.stringify(a)===JSON.stringify(b)}catch{return false}}

  async function pushNow(){
    if(!client||!user||pulling)return;
    status('正在保存到云端…');
    const payload=currentLocal();
    const {error}=await client.from('fitness_snapshots').upsert({user_id:user.id,payload,schema_version:1},{onConflict:'user_id'});
    if(error){status('云端保存失败','bad');console.error(error);return;}
    status('已保存到云端','good');
  }
  function schedulePush(){
    if(!user)return;
    clearTimeout(syncTimer);
    syncTimer=setTimeout(pushNow,700);
  }

  Storage.prototype.setItem=function(k,v){
    originalSetItem.call(this,k,v);
    if(this===localStorage&&k===STORAGE_KEY)schedulePush();
  };

  async function pullOrSeed(){
    if(!client||!user)return;
    pulling=true;status('正在同步…');
    const {data,error}=await client.from('fitness_snapshots').select('payload,updated_at').eq('user_id',user.id).maybeSingle();
    if(error){pulling=false;status('同步失败','bad');console.error(error);return;}
    const local=currentLocal();
    if(!data){
      const {error:seedError}=await client.from('fitness_snapshots').insert({user_id:user.id,payload:local,schema_version:1});
      pulling=false;
      if(seedError){status('首次云端备份失败','bad');console.error(seedError);}else status('现有 Windows 数据已备份到云端','good');
      return;
    }
    const cloud=data.payload||{};
    if(!sameData(local,cloud)){
      // Safety first: never silently discard local history. Merge array records by id/date and prefer local profile edits.
      const merged=mergeSnapshots(cloud,local);
      originalSetItem.call(localStorage,STORAGE_KEY,JSON.stringify(merged));
      if(typeof state!=='undefined') state={...state,...merged};
      if(typeof render==='function') render();
      await client.from('fitness_snapshots').upsert({user_id:user.id,payload:merged,schema_version:1},{onConflict:'user_id'});
    }
    pulling=false;status('云端已同步','good');
  }

  function mergeList(a=[],b=[],identity){
    const out=[],seen=new Set();
    [...a,...b].forEach(x=>{const id=identity(x);if(!seen.has(id)){seen.add(id);out.push(x);}});
    return out;
  }
  function mergeSnapshots(cloud={},local={}){
    const profile={...(cloud.profile||{}),...(local.profile||{})};
    const merged={...cloud,...local,profile};
    merged.meals=mergeList(cloud.meals,local.meals,x=>x.id||`${x.date}|${x.name}|${x.calories}`);
    merged.workouts=mergeList(cloud.workouts,local.workouts,x=>x.id||`${x.date}|${x.split||x.name}`);
    merged.badminton=mergeList(cloud.badminton,local.badminton,x=>x.id||`${x.date}|${x.minutes||0}|${x.calories||0}`);
    merged.weights=mergeList(cloud.weights,local.weights,x=>x.date);
    merged.sleep=mergeList(cloud.sleep,local.sleep,x=>x.date);
    return merged;
  }

  async function signUp(email,password){
    const {error}=await client.auth.signUp({email,password});
    if(error)throw error;
    status('注册成功；如邮箱验证已开启，请先检查邮箱');
  }
  async function signIn(email,password){
    const {error}=await client.auth.signInWithPassword({email,password});
    if(error)throw error;
  }
  async function signOut(){await client.auth.signOut();}

  function openAuth(){
    if(!ready){
      modal(`<h2>云端还未配置</h2><div class="surface-note">代码已经准备好。下一步只需要创建一个 Supabase 项目，并把 Project URL 和 anon/publishable key 填入 cloud-config.js。不会删除现在 Windows 或 iPhone 里的任何数据。</div>`);return;
    }
    if(user){
      modal(`<h2>云端账号</h2><div class="surface-note">已登录：${esc(user.email||'')}</div><div class="quick-row"><button type="button" class="primary" onclick="window.duoduoCloudPush()">立即备份</button><button type="button" class="secondary" onclick="window.duoduoCloudSignOut()">退出登录</button></div>`);return;
    }
    modal(`<h2>登录 / 注册</h2><div class="field"><label>邮箱</label><input id="cloudEmail" type="email" autocomplete="email"></div><div class="field"><label>密码</label><input id="cloudPassword" type="password" minlength="6" autocomplete="current-password"></div><div class="grid2"><button type="button" class="primary" onclick="window.duoduoCloudLogin()">登录</button><button type="button" class="secondary" onclick="window.duoduoCloudRegister()">注册</button></div><div class="surface-note">第一次登录时，如果云端没有数据，会先把当前 Windows 浏览器里的记录上传；不会覆盖掉现有本地数据。</div>`);
  }

  function mountChip(){
    const top=document.querySelector('.topbar');if(!top||document.querySelector('#cloudChip'))return;
    const wrap=document.createElement('div');wrap.className='cloud-actions';wrap.innerHTML=`<button id="cloudChip" class="cloud-chip" type="button"><span class="cloud-dot"></span><span id="cloudStatusText">${ready?'未登录':'待配置'}</span></button>`;
    const add=document.querySelector('#quickAdd');top.insertBefore(wrap,add);wrap.querySelector('#cloudChip').onclick=openAuth;
  }

  async function init(){
    mountChip();
    if(!ready||!window.supabase){status(ready?'云库组件未加载':'待配置');return;}
    client=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
    const {data}=await client.auth.getSession();user=data.session?.user||null;
    if(user){status('已登录，正在同步…');await pullOrSeed();}else status('未登录');
    client.auth.onAuthStateChange(async(_event,session)=>{user=session?.user||null;if(user){closeModal?.();status('已登录，正在同步…');await pullOrSeed();}else status('未登录');});
  }

  window.duoduoCloudLogin=async()=>{try{await signIn(document.querySelector('#cloudEmail').value.trim(),document.querySelector('#cloudPassword').value)}catch(e){alert('登录失败：'+e.message)}};
  window.duoduoCloudRegister=async()=>{try{await signUp(document.querySelector('#cloudEmail').value.trim(),document.querySelector('#cloudPassword').value)}catch(e){alert('注册失败：'+e.message)}};
  window.duoduoCloudSignOut=async()=>{await signOut();closeModal?.();};
  window.duoduoCloudPush=async()=>{await pushNow();closeModal?.();};
  window.duoduoCloudOpen=openAuth;
  window.addEventListener('DOMContentLoaded',init);
})();
