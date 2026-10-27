const h=require('../../utils/helpers');
const app=getApp();

const FALLBACK={
  label:'我的默认早餐',
  name:'250g酸奶 2个燕麦 30g蓝莓 12g南瓜子 香蕉',
  calories:560,
  protein:31,
  carbs:68,
  fat:20
};

Page({
  data:{form:{...FALLBACK},saving:false},
  onLoad(){if(!h.requireLogin())return;this.load();},
  async load(){
    try{
      const s=await app.getSnapshot(true);
      const saved=s.profile?.breakfastTemplate||{};
      this.setData({form:{...FALLBACK,...saved}});
    }catch(e){wx.showToast({title:'读取早餐模板失败',icon:'none'});}
  },
  input(e){
    const key=e.currentTarget.dataset.key;
    const numeric=['calories','protein','carbs','fat'].includes(key);
    this.setData({[`form.${key}`]:numeric?(Number(e.detail.value)||0):e.detail.value});
  },
  reset(){this.setData({form:{...FALLBACK}});},
  async save(){
    const f=this.data.form;
    if(!String(f.name||'').trim()){wx.showToast({title:'写一下早餐内容',icon:'none'});return;}
    this.setData({saving:true});
    try{
      const s=await app.getSnapshot(true);
      s.profile=s.profile||{};
      s.profile.breakfastTemplate={
        label:String(f.label||'我的默认早餐').trim(),
        name:String(f.name||'').trim(),
        calories:h.round(f.calories),protein:h.round(f.protein,1),carbs:h.round(f.carbs,1),fat:h.round(f.fat,1)
      };
      await app.saveSnapshot(s);
      wx.showToast({title:'默认早餐已保存',icon:'success'});
      setTimeout(()=>wx.navigateBack(),450);
    }catch(e){wx.showToast({title:'保存失败',icon:'none'});}
    finally{this.setData({saving:false});}
  }
});
