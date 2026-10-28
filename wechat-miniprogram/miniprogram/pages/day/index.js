const h = require('../../utils/helpers');
const { presentGymSessions } = require('../../utils/calendarMarkers');
const app = getApp();

Page({
  data: { date: '', label: '', meals: [], totals: {}, workouts: [], badminton: [], other: [], weight: '', sleep: '' },
  onLoad(q) {
    this.date = q.date || h.todayKey();
    this.load();
  },
  async load() {
    const s = await app.getSnapshot(true);
    const date = this.date;
    const meals = (s.meals || []).filter(x => x.date === date);
    const workouts = presentGymSessions((s.workouts || []).filter(x => x.date === date)).map(w => ({
      ...w,
      exercises: (w.exercises || []).map(e => ({
        ...e,
        setsText: (e.setEntries || []).map(x => `${h.round(x.weight, 1)}kg × ${x.reps || '-'}${x.rpe ? ` · RPE ${x.rpe}` : ''}`).join('  /  ')
      }))
    }));
    const badminton = (s.badminton || []).filter(x => x.date === date);
    const other = (s.health?.workouts || []).filter(x => x.date === date && x.activityType !== 'functional_strength_training');
    const weight = (s.weights || []).find(x => x.date === date);
    const health = s.health?.daily?.[date] || {};
    const sleep = health.sleepHours || ((s.sleep || []).find(x => x.date === date)?.hours);
    const d = new Date(`${date}T12:00:00`);
    this.setData({
      date,
      label: d.toLocaleDateString('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }),
      meals,
      totals: h.totals(meals),
      workouts,
      badminton,
      other,
      weight: weight ? `${h.round(weight.kg || weight.weight, 1)} kg` : '',
      sleep: sleep ? `${h.round(sleep, 1)} h` : ''
    });
  }
});
