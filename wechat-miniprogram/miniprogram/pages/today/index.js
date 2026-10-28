const h=require('../../utils/helpers');
const { presentGymSessions, presentBadmintonSessions, otherHealthWorkouts } = require('../../utils/calendarMarkers');
const app=getApp();

const FALLBACK_BREAKFAST={
  label:'我的默认早餐',
  name:'250g酸奶 2个燕麦 30g蓝莓 12g南瓜子 香蕉',
  calories:560,
  protein:31,
  carbs:68,
  fat:20
};

function goal(profile,key,fallback){
  const candidates={calories:['calorieTarget','dailyCalories','calories'],protein:['proteinTarget','dailyProtein','protein'],carbs:['carbTarget','dailyCarbs','carbs'],fat:['fatTarget','dailyFat','fat']}[key]||[];
  for(const k of candidates){if(Number(profile?.[k]))return Number(profile[k]);}
  return fallback;
}

function isDefaultBreakfast(meal,date,template){
  return meal?.date===date&&(meal?.source==='default-breakfast-wechat'||meal?.templateId==='default-breakfast'||meal?.name===template.name);
}

Page({
  data:{
    loading:true,date:'',calories:0,remain:0,goal:2700,
    protein:0,proteinGoal:130,carbs:0,carbGoal:350,fat:0,fatGoal:80,
    proteinPct:0,carbPct:0,fatPct:0,meals:[],activities:[],weight:'--',weightInput:'',weightSaving:false,
    breakfast:FALLBACK_BREAKFAST,breakfastLogged:false,breakfastSaving:false
  },
  onShow(){
    if(this.getTabBar)this.getTabBar()?.setData({selected:0});
    if(!h.requireLogin())return;
    this.load();
  },
  async load(){
    this.setData({loading:true});
    try{
      const s=await app.getSnapshot(true);
      const date=h.todayKey();
      const template={...FALLBACK_BREAKFAST,...(s.profile?.breakfastTemplate||{})};
      const meals=(s.meals||[]).filter(x=>x.date===date);
      const t=h.totals(meals),p=s.profile||{};
      const calorieGoal=goal(p,'calories',2700),proteinGoal=goal(p,'protein',130),carbGoal=goal(p,'carbs',350),fatGoal=goal(p,'fat',80);
      const gyms=presentGymSessions((s.workouts||[]).filter(x=>x.date===date)).map(x=>({icon:'🏋',name:x.split||x.name||'健身',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
      const healthToday=(s.health?.workouts||[]).filter(x=>x.date===date);
      const bad=presentBadmintonSessions((s.badminton||[]).filter(x=>x.date===date), healthToday).map(x=>({icon:'🏸',name:'羽毛球',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
      const other=otherHealthWorkouts(healthToday).map(x=>({icon:'⌚',name:x.name||'Watch 锻炼',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
      const weights=[...(s.weights||[])].sort((a,b)=>String(b.date).localeCompare(String(a.date)));
      this.setData({
        loading:false,
        date:new Date().toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'long'}),
        calories:Math.round(t.calories),remain:Math.max(0,Math.round(calorieGoal-t.calories)),goal:calorieGoal,
        protein:Math.round(t.protein),proteinGoal,carbs:Math.round(t.carbs),carbGoal,fat:Math.round(t.fat),fatGoal,
        proteinPct:Math.min(100,Math.round(t.protein/proteinGoal*100)),
        carbPct:Math.min(100,Math.round(t.carbs/carbGoal*100)),
        fatPct:Math.min(100,Math.round(t.fat/fatGoal*100)),
        meals,activities:[...gyms,...bad,...other],
        weight:weights[0]?`${Number(weights[0].kg||weights[0].weight||0).toFixed(1)} kg`:'--',
        weightInput:(()=>{const today=(s.weights||[]).find(x=>x.date===date);return today?String(h.round(Number(today.kg||today.weight||0),1)):'';})(),
        breakfast:template,
        breakfastLogged:meals.some(m=>isDefaultBreakfast(m,date,template)),
        breakfastSaving:false
      });
    }catch(e){
      if(e.message==='NOT_SIGNED_IN')wx.reLaunch({url:'/pages/login/index'});
      else wx.showToast({title:'同步失败',icon:'none'});
      this.setData({loading:false,breakfastSaving:false});
    }
  },
  async addBreakfast(){
    if(this.data.breakfastLogged||this.data.breakfastSaving){
      if(this.data.breakfastLogged)wx.showToast({title:'今天早餐已经记录过了',icon:'none'});
      return;
    }
    this.setData({breakfastSaving:true});
    try{
      const s=await app.getSnapshot(true);
      const date=h.todayKey();
      const template={...FALLBACK_BREAKFAST,...(s.profile?.breakfastTemplate||{})};
      s.meals=Array.isArray(s.meals)?s.meals:[];
      if(s.meals.some(m=>isDefaultBreakfast(m,date,template))){
        this.setData({breakfastLogged:true,breakfastSaving:false});
        wx.showToast({title:'今天早餐已经记录过了',icon:'none'});
        return;
      }
      s.meals.push({id:h.id(),date,name:template.name,calories:h.num(template.calories),protein:h.num(template.protein),carbs:h.num(template.carbs),fat:h.num(template.fat),source:'default-breakfast-wechat',templateId:'default-breakfast'});
      await app.saveSnapshot(s);
      wx.showToast({title:'早餐已记录',icon:'success'});
      await this.load();
    }catch(e){
      wx.showToast({title:'早餐记录失败',icon:'none'});
      this.setData({breakfastSaving:false});
    }
  },
  weightInput(e){this.setData({weightInput:e.detail.value});},
  async saveWeight(){
    if(this.data.weightSaving)return;
    const kg=h.round(h.num(this.data.weightInput),1);
    if(!kg||kg<20||kg>200){wx.showToast({title:'请输入 20-200 kg 的体重',icon:'none'});return;}
    this.setData({weightSaving:true});
    try{
      const s=await app.getSnapshot(true);
      const date=h.todayKey();
      s.weights=Array.isArray(s.weights)?s.weights:[];
      s.weights=s.weights.filter(x=>x.date!==date);
      s.weights.push({id:h.id(),date,kg});
      await app.saveSnapshot(s);
      wx.showToast({title:'体重已记录',icon:'success'});
      await this.load();
    }catch(e){
      wx.showToast({title:'体重记录失败',icon:'none'});
    }finally{
      this.setData({weightSaving:false});
    }
  },
  editBreakfast(){wx.navigateTo({url:'/pages/breakfast/index'});},
  photo(){wx.switchTab({url:'/pages/camera/index'});},
  workout(){wx.navigateTo({url:'/pages/workout/index'});},
  calendar(){wx.switchTab({url:'/pages/calendar/index'});}
});
