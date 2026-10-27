Component({
  data:{selected:0,list:[
    {pagePath:'/pages/today/index',text:'今天',icon:'◉'},
    {pagePath:'/pages/food/index',text:'饮食',icon:'◌'},
    {pagePath:'/pages/camera/index',text:'记录',icon:'+'},
    {pagePath:'/pages/calendar/index',text:'日历',icon:'▦'},
    {pagePath:'/pages/progress/index',text:'进展',icon:'↗'}
  ]},
  methods:{switchTab(e){const {path,index}=e.currentTarget.dataset;this.setData({selected:Number(index)});wx.switchTab({url:path});}}
});
