const BODY_PARTS = ['胸', '肩', '背', '腿'];

// Apple Watch strength imports land in workouts[] with split "健身" and no exercises.
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

function splitText(workout) {
  if (!workout) return '';
  const split = workout.split == null ? '' : String(workout.split).trim();
  if (split) return split;
  return workout.name == null ? '' : String(workout.name).trim();
}

function isGenericSplit(raw) {
  const text = String(raw || '').trim();
  if (!text) return true;
  return GENERIC_SPLITS.has(text) || GENERIC_SPLITS.has(text.toLowerCase());
}

// A non-standard split that is already a short Chinese label (核心, 手臂) stays readable.
function shortExtra(raw) {
  const cjk = String(raw || '').replace(/[^\u4e00-\u9fff]/g, '');
  if (cjk.length >= 1 && cjk.length <= 2) return cjk;
  return '';
}

// One compact label for every gym workout on a day.
// Body parts stay in 胸肩背腿 order so 肩 + 胸 renders as 胸肩.
// Generic splits become 练, and only when the day has no more specific label.
function gymSplitLabel(workouts) {
  const list = Array.isArray(workouts) ? workouts : [];
  if (!list.length) return '';
  const parts = new Set();
  const extras = [];
  let generic = false;
  for (const workout of list) {
    const raw = splitText(workout);
    const found = BODY_PARTS.filter(part => raw.includes(part));
    if (found.length) {
      found.forEach(part => parts.add(part));
      continue;
    }
    const extra = isGenericSplit(raw) ? '' : shortExtra(raw);
    if (extra) {
      if (!extras.includes(extra)) extras.push(extra);
      continue;
    }
    generic = true;
  }
  const specific = BODY_PARTS.filter(part => parts.has(part)).concat(extras).join('');
  if (specific) return specific;
  return generic ? '练' : '';
}

function markerLayout(label) {
  const length = Array.from(label || '').length;
  return { gymSize: length >= 4 ? 'long' : '' };
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
    const bad = sameDay(source.badminton, date).length;
    const watch = sameDay(source.health && source.health.workouts, date)
      .filter(item => item.activityType !== 'functional_strength_training').length;
    const gymLabel = gymSplitLabel(dayWorkouts);
    const layout = markerLayout(gymLabel);
    cells.push({
      key: date,
      date,
      day,
      today: date === today,
      meals,
      workouts: dayWorkouts.length,
      bad,
      watch,
      gymLabel,
      gymSize: layout.gymSize,
      has: Boolean(meals || dayWorkouts.length || bad || watch)
    });
  }
  return {
    year,
    month: month + 1,
    title: `${year}年 ${month + 1}月`,
    cells
  };
}

module.exports = { gymSplitLabel, markerLayout, buildCalendarCells };
