const api = require('./utils/api');

App({
  globalData: { snapshot: null },
  onLaunch() { api.restoreSession(); },
  async getSnapshot(force = false) {
    if (!force && this.globalData.snapshot) return this.globalData.snapshot;
    const snapshot = await api.getSnapshot();
    this.globalData.snapshot = snapshot || {};
    return this.globalData.snapshot;
  },
  async saveSnapshot(snapshot) {
    this.globalData.snapshot = snapshot;
    await api.saveSnapshot(snapshot);
    return snapshot;
  }
});
