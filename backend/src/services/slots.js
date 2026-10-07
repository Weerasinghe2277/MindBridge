// Real-time availability (FR2): bookable slots are generated from each staff
// member's weekly schedule, minus blocked time, minus already-held bookings.
const Appointment = require('../models/Appointment');
const { Consultation } = require('../models');
const { ACTIVE } = Appointment;
const T = require('../utils/time');
const { getSettings } = require('./settings');

const DEFAULT_AVAILABILITY = {
  workingDays: [1, 2, 3, 4, 5], startTime: '09:00', endTime: '16:30',
  lunchBreak: { enabled: true, start: '12:30', end: '13:30' }, sessionLength: 30, bufferMinutes: 0, blocks: [],
};

function blocksForDate(av, dateStr) {
  const wd = T.weekdayOf(dateStr);
  return (av.blocks || []).filter((b) => b.date === dateStr || (b.repeatWeekly && b.date <= dateStr && T.weekdayOf(b.date) === wd));
}

// Pure schedule for one day: candidate slot start times ('HH:MM'), ignoring bookings.
function scheduleForDate(availability, dateStr) {
  const av = availability || DEFAULT_AVAILABILITY;
  if (!(av.workingDays || []).includes(T.weekdayOf(dateStr))) return [];
  const len = av.sessionLength || 30;
  const step = len + (av.bufferMinutes || 0);
  const open = T.toMinutes(av.startTime);
  const close = T.toMinutes(av.endTime);
  const lunch = av.lunchBreak?.enabled ? [T.toMinutes(av.lunchBreak.start), T.toMinutes(av.lunchBreak.end)] : null;
  const blocks = blocksForDate(av, dateStr).map((b) => (b.allDay ? [0, 24 * 60] : [T.toMinutes(b.from), T.toMinutes(b.to)]));
  const overlaps = (s, e, [a, b]) => s < b && e > a;
  const out = [];
  for (let s = open; s + len <= close; s += step) {
    const e = s + len;
    if (lunch && overlaps(s, e, lunch)) {
      // Resume immediately after lunch so the afternoon starts on time.
      if (s < lunch[1]) { s = lunch[1] - step; }
      continue;
    }
    if (blocks.some((b) => overlaps(s, e, b))) continue;
    out.push(T.fromMinutes(s));
  }
  return out;
}

async function busyStartsFor(staff, role, dayStart, dayEnd, excludeId) {
  if (role === 'doctor') {
    const cons = await Consultation.find({ doctor: staff._id, status: { $in: ['scheduled', 'in_progress'] }, start: { $gte: dayStart, $lt: dayEnd } }).select('start').lean();
    return new Set(cons.filter((c) => String(c._id) !== String(excludeId)).map((c) => c.start.getTime()));
  }
  const appts = await Appointment.find({
    counsellor: staff._id,
    status: { $in: ACTIVE },
    $or: [{ start: { $gte: dayStart, $lt: dayEnd } }, { 'proposal.start': { $gte: dayStart, $lt: dayEnd } }],
  }).select('start proposal status').lean();
  const set = new Set();
  for (const a of appts) {
    if (String(a._id) === String(excludeId)) continue;
    set.add(a.start.getTime());
    if (a.proposal?.start && ['reschedule_requested', 'reschedule_proposed'].includes(a.status)) set.add(a.proposal.start.getTime());
  }
  return set;
}

// Slots for one day with availability flags. `excludeId` lets a booking being rescheduled ignore itself.
async function slotsForDate(staff, dateStr, { excludeId, role = staff.role } = {}) {
  const settings = await getSettings();
  const av = staff.availability || DEFAULT_AVAILABILITY;
  const today = T.todayStr();
  const lastDay = T.addDays(today, settings.appointments.bookingWindowDays);
  if (dateStr < today || dateStr > lastDay) return [];
  const times = scheduleForDate(av, dateStr);
  if (!times.length) return [];
  const dayStart = T.fromLocal(dateStr, '00:00');
  const dayEnd = new Date(dayStart.getTime() + T.DAY_MS);
  const busy = await busyStartsFor(staff, role, dayStart, dayEnd, excludeId);
  const now = Date.now();
  const len = av.sessionLength || 30;
  return times.map((time) => {
    const start = T.fromLocal(dateStr, time);
    let reason = null;
    if (start.getTime() <= now + 15 * 60 * 1000) reason = 'past';
    else if (busy.has(start.getTime())) reason = 'booked';
    return { time, start: start.toISOString(), end: new Date(start.getTime() + len * 60000).toISOString(), available: !reason, reason };
  });
}

// Month overview for the booking calendar: which days have free slots.
async function monthOverview(staff, monthStr, opts = {}) {
  const [y, m] = monthStr.split('-').map(Number);
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const days = [];
  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = `${monthStr}-${String(d).padStart(2, '0')}`;
    const slots = await slotsForDate(staff, dateStr, opts);
    const free = slots.filter((s) => s.available).length;
    days.push({ date: dateStr, total: slots.length, free, working: slots.length > 0 });
  }
  return days;
}

async function nextAvailable(staff, opts = {}) {
  const settings = await getSettings();
  const today = T.todayStr();
  for (let i = 0; i <= settings.appointments.bookingWindowDays; i++) {
    const dateStr = T.addDays(today, i);
    const slots = await slotsForDate(staff, dateStr, opts);
    const s = slots.find((x) => x.available);
    if (s) return { date: dateStr, ...s, freeToday: i === 0 ? slots.filter((x) => x.available).length : 0 };
  }
  return null;
}

// Validates that a requested start time is a real, free slot for this staff member.
async function assertSlotFree(staff, startIso, opts = {}) {
  const start = new Date(startIso);
  if (Number.isNaN(start.getTime())) return { ok: false, reason: 'invalid' };
  const dateStr = T.local(start).dateStr;
  const slots = await slotsForDate(staff, dateStr, opts);
  const slot = slots.find((s) => new Date(s.start).getTime() === start.getTime());
  if (!slot) return { ok: false, reason: 'not_offered' };
  if (!slot.available) return { ok: false, reason: slot.reason };
  return { ok: true, slot };
}

module.exports = { scheduleForDate, slotsForDate, monthOverview, nextAvailable, assertSlotFree, DEFAULT_AVAILABILITY };
