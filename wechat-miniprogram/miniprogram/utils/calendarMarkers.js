const BODY_PARTS = ['胸', '肩', '背', '腿'];

// Watch strength imports are stored as workouts with a generic split and no exercises.
// They carry duration, calories, and heart rate for the user's own session.
const GENERIC_SPLITS = new Set([
  '健身',
  '练',
  '力量',
  '力量训练',
  '功能性力量',
  '功能性力量训练',
  '训练',
  'gym',
  'workout',
  'strength',
  'strength training',
  'functional strength',
  'functional strength training'
]);

function pad(n) {
  return String(n).padStart(2, '0');
}

function isGenericSplit(raw) {
  const text = String(raw || '').trim();
  if (!text) return true;
  return GENERIC_SPLITS.has(text) || GENERIC_SPLITS.has(text.toLowerCase());
}

function hasExerciseDetail(workout) {
  const exercises = Array.isArray(workout && workout.exercises) ? workout.exercises : [];
  return exercises.some(exercise => {
    if (!exercise || typeof exercise !== 'object') return false;
    if (String(exercise.name || '').trim()) return true;
    if (Array.isArray(exercise.setEntries) && exercise.setEntries.length) return true;
    if (Number(exercise.weight) || Number(exercise.reps) || Number(exercise.sets)) return true;
    return false;
  });
}

function isImportedStrength(workout) {
  const source = String(workout.source || '');
  const activity = String(workout.activityType || '').toLowerCase();
  const name = String(workout.name || '').trim();
  return source === 'apple-health-strength'
    || activity === 'functional_strength_training'
    || name === '功能性力量训练'
    || /functional strength/i.test(`${name} ${activity}`);
}

// A watch strength import with no user split and no exercises. Display-only;
// the stored snapshot is left untouched.
function isWatchOnlyStrength(workout) {
  if (!workout || typeof workout !== 'object') return false;
  const split = String(workout.split || '').trim();
  if (BODY_PARTS.includes(split)) return false;
  if (hasExerciseDetail(workout)) return false;
  if (isImportedStrength(workout)) return true;
  return isGenericSplit(split);
}

// The user's split, as a single label. Several workouts are not joined.
function oneSplitLabel(split) {
  const raw = String(split || '').trim();
  if (!raw || isGenericSplit(raw)) return '';
  const parts = BODY_PARTS.filter(part => raw.includes(part));
  if (parts.length) return parts[0];
  return Array.from(raw).length <= 2 ? raw : '';
}

function gymSplitLabel(workouts) {
  const list = Array.isArray(workouts) ? workouts : [];
  for (const workout of list) {
    if (!workout || isWatchOnlyStrength(workout)) continue;
    const label = oneSplitLabel(workout.split || workout.name);
    if (label) return label;
  }
  return '';
}

function positive(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function withWatchMetrics(manual, watches) {
  const next = { ...manual };
  for (const watch of watches) {
    if (!positive(next.minutes) && positive(watch.minutes)) next.minutes = watch.minutes;
    if (!positive(next.calories) && positive(watch.calories)) next.calories = watch.calories;
    for (const key of ['watchHeartRateAvg', 'watchHeartRateMin', 'watchHeartRateMax', 'watchWorkoutId', 'watchStart', 'watchEnd']) {
      if ((next[key] == null || next[key] === '') && watch[key] != null && watch[key] !== '') next[key] = watch[key];
    }
    if (!next.metricsSource && (watch.metricsSource || isImportedStrength(watch))) next.metricsSource = watch.metricsSource || 'apple-watch';
  }
  return next;
}

// Collapse a watch strength import into the manual session on the same day.
// A day that only has the import stays a single metrics record, with no invented split.
function presentGymSessions(workouts) {
  const list = Array.isArray(workouts) ? workouts : [];
  const watchByDate = new Map();
  const manualDates = new Set();
  for (const workout of list) {
    if (!workout) continue;
    const date = String(workout.date || '');
    if (isWatchOnlyStrength(workout)) {
      if (!watchByDate.has(date)) watchByDate.set(date, []);
      watchByDate.get(date).push(workout);
    } else {
      manualDates.add(date);
    }
  }
  const attached = new Set();
  const out = [];
  for (const workout of list) {
    if (!workout) continue;
    const date = String(workout.date || '');
    if (isWatchOnlyStrength(workout)) {
      if (!manualDates.has(date)) out.push(workout);
      continue;
    }
    if (attached.has(date)) {
      out.push(workout);
      continue;
    }
    attached.add(date);
    const watches = watchByDate.get(date) || [];
    out.push(watches.length ? withWatchMetrics(workout, watches) : workout);
  }
  return out;
}

function sameDay(list, date) {
  return (Array.isArray(list) ? list : []).filter(item => item && item.date === date);
}

function buildCalendarCells({ year, monthIndex, today, snapshot }) {
  const month = monthIndex;
  const first = new Date(year, month, 1);
  const lead = (first.getDay() + 6) % 7;
  const days = new Date(year, month + 1, 0).getDate();
  const source = snapshot || {};
  const cells = [];
  for (let i = 0; i < lead; i++) cells.push({ blank: true, key: `b${i}` });
  for (let day = 1; day <= days; day++) {
    const date = `${year}-${pad(month + 1)}-${pad(day)}`;
    const dayWorkouts = sameDay(source.workouts, date);
    const meals = sameDay(source.meals, date).length;
    // Recorded badminton entries only. Nothing is inferred from plans or other workouts.
    const bad = sameDay(source.badminton, date).length;
    const watch = sameDay(source.health && source.health.workouts, date)
      .filter(item => item.activityType !== 'functional_strength_training').length;
    const manual = dayWorkouts.filter(item => !isWatchOnlyStrength(item)).length;
    const gymLabel = gymSplitLabel(dayWorkouts);
    cells.push({
      key: date,
      date,
      day,
      today: date === today,
      meals,
      workouts: manual,
      bad,
      watch,
      gymLabel,
      gymSize: '',
      has: Boolean(meals || manual || bad || watch)
    });
  }
  return {
    year,
    month: month + 1,
    title: `${year}年 ${month + 1}月`,
    cells
  };
}

module.exports = {
  gymSplitLabel,
  isWatchOnlyStrength,
  presentGymSessions,
  buildCalendarCells
};
