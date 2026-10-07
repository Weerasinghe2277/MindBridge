// Sri Lanka has a fixed UTC+5:30 offset with no daylight saving, so local
// calendar maths can be done with a constant offset instead of a tz library.
const env = require('../config/env');

const OFFSET_MS = env.tzOffsetMinutes * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const pad = (n) => String(n).padStart(2, '0');

function local(date) {
  const d = new Date(new Date(date).getTime() + OFFSET_MS);
  const jsDay = d.getUTCDay();
  return {
    y: d.getUTCFullYear(),
    m: d.getUTCMonth() + 1,
    d: d.getUTCDate(),
    hh: d.getUTCHours(),
    mm: d.getUTCMinutes(),
    weekday: jsDay === 0 ? 7 : jsDay, // ISO: Mon=1 … Sun=7
    dateStr: `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`,
    time: `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`,
  };
}

const isDateStr = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));
const isTimeStr = (s) => typeof s === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);

// Local date + 'HH:MM' -> UTC Date
function fromLocal(dateStr, time = '00:00') {
  const [y, m, d] = dateStr.split('-').map(Number);
  const [hh, mm] = time.split(':').map(Number);
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - OFFSET_MS);
}

const todayStr = () => local(new Date()).dateStr;

function addDays(dateStr, n) {
  const t = Date.parse(dateStr + 'T00:00:00Z') + n * DAY_MS;
  return new Date(t).toISOString().slice(0, 10);
}

function weekdayOf(dateStr) {
  const js = new Date(dateStr + 'T00:00:00Z').getUTCDay();
  return js === 0 ? 7 : js;
}

const toMinutes = (t) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};
const fromMinutes = (n) => `${pad(Math.floor(n / 60))}:${pad(n % 60)}`;

function fmtTime(date) {
  const l = local(date);
  const h12 = l.hh % 12 === 0 ? 12 : l.hh % 12;
  return `${h12}:${pad(l.mm)} ${l.hh < 12 ? 'AM' : 'PM'}`;
}

// "Thu, 8 Oct · 10:30 AM"
function fmtDateTime(date) {
  const l = local(date);
  const js = l.weekday % 7;
  return `${WD[js]}, ${l.d} ${MON[l.m - 1]} · ${fmtTime(date)}`;
}

function fmtDate(date) {
  const l = local(date);
  return `${WD[l.weekday % 7]}, ${l.d} ${MON[l.m - 1]} ${l.y}`;
}

// Monday of the local week containing dateStr
function weekStart(dateStr) {
  return addDays(dateStr, -(weekdayOf(dateStr) - 1));
}

module.exports = {
  DAY_MS, local, fromLocal, todayStr, addDays, weekdayOf, toMinutes, fromMinutes,
  fmtTime, fmtDateTime, fmtDate, weekStart, isDateStr, isTimeStr,
};
