const pad = n => String(n).padStart(2, '0');
const todayKey = () => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`; };
const id = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2,10)}`;
const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const round = (v, d = 0) => { const p = 10 ** d; return Math.round(num(v) * p) / p; };
const totals = meals => (meals || []).reduce((a,m)=>({calories:a.calories+num(m.calories),protein:a.protein+num(m.protein),carbs:a.carbs+num(m.carbs),fat:a.fat+num(m.fat)}),{calories:0,protein:0,carbs:0,fat:0});
function requireLogin() { const api = require('./api'); if (!api.restoreSession()) { wx.reLaunch({url:'/pages/login/index'}); return false; } return true; }
module.exports = { pad, todayKey, id, num, round, totals, requireLogin };
