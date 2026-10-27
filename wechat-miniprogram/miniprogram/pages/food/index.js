const h=require('../../utils/helpers');
const app=getApp();

Page({
  data:{
    meals:[],
    totals:{calories:0,protein:0,carbs:0,fat:0},
    deletingId:''
  },
  onShow(){
    this.getTabBar?.()?.setData({selected:1});
    if(!h.requireLogin())return;
    this.load();
  },
  async load(){
    try{
      const s=await app.getSnapshot(true);
      const date=h.todayKey();
      const meals=(s.meals||[]).filter(x=>x.date===date);
      this.setData({meals,totals:h.totals(meals),deletingId:''});
    }catch(e){
      wx.showToast({title:'读取失败',icon:'none'});
    }
  },
  record(){wx.switchTab({url:'/pages/camera/index'});},
  deleteMeal(e){
    const id=e.currentTarget.dataset.id;
    const meal=this.data.meals.find(x=>x.id===id);
    if(!id||!meal||this.data.deletingId)return;
    wx.showModal({
      title:'删除这条记录？',
      content:`${meal.name||'这一餐'} · ${Math.round(Number(meal.calories)||0)} kcal`,
      confirmText:'删除',
      confirmColor:'#C65F57',
      cancelText:'取消',
      success:async res=>{
        if(!res.confirm)return;
        this.setData({deletingId:id});
        try{
          const s=await app.getSnapshot(true);
          s.meals=(Array.isArray(s.meals)?s.meals:[]).filter(x=>x.id!==id);
          await app.saveSnapshot(s);
          wx.showToast({title:'已删除',icon:'success'});
          await this.load();
        }catch(err){
          this.setData({deletingId:''});
          wx.showToast({title:'删除失败',icon:'none'});
        }
      }
    });
  }
});
