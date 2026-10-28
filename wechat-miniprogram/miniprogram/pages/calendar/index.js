const h = require('../../utils/helpers');
const { buildCalendarCells } = require('../../utils/calendarMarkers');
const app = getApp();

Page({
  data: { year: 0, month: 0, title: '', cells: [], loading: true },
  onLoad() {
    const d = new Date();
    this.cursor = new Date(d.getFullYear(), d.getMonth(), 1);
  },
  onShow() {
    this.getTabBar?.()?.setData({ selected: 3 });
    if (!h.requireLogin()) return;
    this.load();
  },
  async load() {
    this.snapshot = await app.getSnapshot(true);
    this.renderMonth();
  },
  renderMonth() {
    const view = buildCalendarCells({
      year: this.cursor.getFullYear(),
      monthIndex: this.cursor.getMonth(),
      today: h.todayKey(),
      snapshot: this.snapshot || {}
    });
    this.setData({ ...view, loading: false });
  },
  move(e) {
    const delta = Number(e.currentTarget.dataset.delta);
    this.cursor = new Date(this.cursor.getFullYear(), this.cursor.getMonth() + delta, 1);
    this.renderMonth();
  },
  today() {
    const d = new Date();
    this.cursor = new Date(d.getFullYear(), d.getMonth(), 1);
    this.renderMonth();
  },
  open(e) {
    const date = e.currentTarget.dataset.date;
    if (date) wx.navigateTo({ url: `/pages/day/index?date=${date}` });
  }
});
