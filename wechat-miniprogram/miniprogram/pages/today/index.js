const h=require('../../utils/helpers');
const app=getApp();

const DEFAULT_BREAKFAST={
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

function isDefaultBreakfast(meal,date){
  return meal?.date===date&&(meal?.source==='default-breakfast-wechat'||meal?.name===DEFAULT_BREAKFAST.name);
}

Page({
  data:{
    loading:true,date:'',calories:0,remain:0,goal:2700,
    protein:0,proteinGoal:130,carbs:0,carbGoal:350,fat:0,fatGoal:80,
    proteinPct:0,carbPct:0,fatPct:0,meals:[],activities:[],weight:'--',
    breakfast:DEFAULT_BREAKFAST,breakfastLogged:false,breakfastSaving:false
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
      const meals=(s.meals||[]).filter(x=>x.date===date);
      const t=h.totals(meals),p=s.profile||{};
      const calorieGoal=goal(p,'calories',2700),proteinGoal=goal(p,'protein',130),carbGoal=goal(p,'carbs',350),fatGoal=goal(p,'fat',80);
      const gyms=(s.workouts||[]).filter(x=>x.date===date).map(x=>({icon:'🏋',name:x.split||x.name||'健身',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
      const bad=(s.badminton||[]).filter(x=>x.date===date).map(x=>({icon:'🏸',name:'羽毛球',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
      const other=(s.health?.workouts||[]).filter(x=>x.date===date&&x.activityType!=='functional_strength_training').map(x=>({icon:'⌚',name:x.name||'Watch 锻炼',meta:[x.minutes?`${Math.round(x.minutes)} 分钟`:'',x.calories?`${Math.round(x.calories)} kcal`:''].filter(Boolean).join(' · ')}));
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
        breakfastLogged:meals.some(m=>isDefaultBreakfast(m,date)),
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
      s.meals=Array.isArray(s.meals)?s.meals:[];
      if(s.meals.some(m=>isDefaultBreakfast(m,date))){
        this.setData({breakfastLogged:true,breakfastSaving:false});
        wx.showToast({title:'今天早餐已经记录过了',icon:'none'});
        return;
      }
      s.meals.push({
        id:h.id(),date,...DEFAULT_BREAKFAST,
        source:'default-breakfast-wechat'
      });
      await app.saveSnapshot(s);
      wx.showToast({title:'早餐已记录',icon:'success'});
      await this.load();
    }catch(e){
      wx.showToast({title:'早餐记录失败',icon:'none'});
      this.setData({breakfastSaving:false});
    }
  },
  photo(){wx.switchTab({url:'/pages/camera/index'});},
  workout(){wx.navigateTo({url:'/pages/workout/index'});},
  calendar(){wx.switchTab({url:'/pages/calendar/index'});}
});
