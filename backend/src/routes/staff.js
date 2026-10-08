// Counsellor & doctor workspace: dashboard and calendar (FR2, FR6).
// Availability (working hours and blocks) is in modules/availability.
const express = require('express');
const Appointment = require('../models/Appointment');
const User = require('../models/User');
const { Referral } = require('../models');
const { requireAuth, requireRole, requireVerified } = require('../middleware/auth');
const { serialize } = require('../services/appointments');
const { slotsForDate, scheduleForDate, DEFAULT_AVAILABILITY } = require('../services/slots');
const T = require('../utils/time');
const { badRequest } = require('../utils/errors');

const { ACTIVE } = Appointment;
const router = express.Router();
router.use(requireAuth, requireRole('counsellor', 'doctor'), requireVerified);

const POP = [
  { path: 'student', select: 'name studentId faculty year' },
  { path: 'counsellor', select: 'name professional' },
];

router.get('/dashboard', requireRole('counsellor'), async (req, res) => {
  const me = req.user._id;
  const now = new Date();
  const d = T.todayStr();
  const dayStart = T.fromLocal(d);
  const dayEnd = T.fromLocal(T.addDays(d, 1));
  const [pending, today, next, flagged] = await Promise.all([
    Appointment.find({ counsellor: me, status: { $in: ['pending', 'reschedule_requested'] }, end: { $gt: now } }).sort({ createdAt: 1 }).populate(POP),
    Appointment.find({ counsellor: me, status: { $in: ['confirmed', 'reschedule_requested', 'reschedule_proposed', 'completed'] }, start: { $gte: dayStart, $lt: dayEnd } }).sort({ start: 1 }).populate(POP),
    Appointment.findOne({ counsellor: me, status: 'confirmed', end: { $gt: now } }).sort({ start: 1 }).populate(POP),
    Appointment.find({ counsellor: me, status: 'pending', 'duplicateOf.0': { $exists: true }, end: { $gt: now } }).populate(POP),
  ]);
  let nextSessionNumber = null;
  if (next && !next.anonymous) nextSessionNumber = 1 + await Appointment.countDocuments({ counsellor: me, student: next.student._id, status: 'completed', anonymous: { $ne: true } });
  res.json({
    pendingCount: pending.length,
    todayCount: today.filter((a) => a.status !== 'completed').length,
    duplicates: flagged.map((a) => serialize(a, 'counsellor')),
    next: next ? { ...serialize(next, 'counsellor'), sessionNumber: nextSessionNumber } : null,
    today: today.map((a) => serialize(a, 'counsellor')),
    pending: pending.map((a) => serialize(a, 'counsellor')),
  });
});

// Calendar month marks: booked vs pending per day.
router.get('/calendar', requireRole('counsellor'), async (req, res) => {
  const month = String(req.query.month || T.todayStr().slice(0, 7));
  if (!/^\d{4}-\d{2}$/.test(month)) throw badRequest('Invalid month');
  const from = T.fromLocal(`${month}-01`);
  const [y, m] = month.split('-').map(Number);
  const to = T.fromLocal(`${m === 12 ? y + 1 : y}-${String(m === 12 ? 1 : m + 1).padStart(2, '0')}-01`);
  const appts = await Appointment.find({ counsellor: req.user._id, status: { $in: [...ACTIVE, 'completed'] }, start: { $gte: from, $lt: to } }).select('start status').lean();
  const days = {};
  for (const a of appts) {
    const ds = T.local(a.start).dateStr;
    days[ds] = days[ds] || { booked: 0, pending: 0 };
    if (a.status === 'pending' || a.status === 'reschedule_requested') days[ds].pending += 1; else days[ds].booked += 1;
  }
  res.json({ month, days });
});

// Everything on one day: blocks, sessions, requests and how many slots are still open.
router.get('/day', requireRole('counsellor'), async (req, res) => {
  const date = String(req.query.date || T.todayStr());
  if (!T.isDateStr(date)) throw badRequest('Invalid date');
  const appts = await Appointment.find({ counsellor: req.user._id, status: { $in: [...ACTIVE, 'completed'] }, start: { $gte: T.fromLocal(date), $lt: T.fromLocal(T.addDays(date, 1)) } }).sort({ start: 1 }).populate(POP);
  const av = req.user.availability || DEFAULT_AVAILABILITY;
  const wd = T.weekdayOf(date);
  const blocks = (av.blocks || []).filter((b) => b.date === date || (b.repeatWeekly && b.date <= date && T.weekdayOf(b.date) === wd));
  const slots = await slotsForDate(req.user, date);
  const open = slots.filter((s) => s.available);
  res.json({
    date,
    appointments: appts.map((a) => serialize(a, 'counsellor')),
    blocks: blocks.map((b) => ({ id: b._id.toString(), from: b.from, to: b.to, allDay: b.allDay, reason: b.reason, repeatWeekly: b.repeatWeekly })),
    openSlots: open.map((s) => s.time),
    working: scheduleForDate(av, date).length > 0,
  });
});

// Doctors available for referral (counsellor side).
router.get('/doctors', requireRole('counsellor'), async (req, res) => {
  const docs = await User.find({ role: 'doctor', status: 'active', 'verification.status': 'approved' });
  const out = [];
  for (const d of docs) {
    const open = await Referral.countDocuments({ doctor: d._id, status: 'new' });
    out.push({ id: d.id, name: d.name, initials: d.initials, title: d.professional?.title, office: d.professional?.office || 'University Medical Centre', openReferrals: open });
  }
  res.json({ doctors: out });
});

module.exports = router;
