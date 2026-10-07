// MEMBER 1 — Availability Management (CRUD 2)
// Add available slot (working hours / blocks), view slots, edit slot settings, remove slot (block).
// Used by counsellors and doctors. Slot maths lives in services/slots.js.
const express = require('express');
const Appointment = require('../../models/Appointment');
const User = require('../../models/User');
const { Consultation } = require('../../models');
const { requireAuth, requireRole, requireVerified } = require('../../middleware/auth');
const { body, z } = require('../../middleware/validate');
const { slotsForDate, scheduleForDate, DEFAULT_AVAILABILITY } = require('../../services/slots');
const T = require('../../utils/time');
const { badRequest, conflict, notFound } = require('../../utils/errors');

const { ACTIVE } = Appointment;
const router = express.Router();
router.use(requireAuth, requireRole('counsellor', 'doctor'), requireVerified);

// ---------- Availability ----------
function availabilityOut(user) {
  const av = user.availability?.toObject ? user.availability.toObject() : (user.availability || DEFAULT_AVAILABILITY);
  return { ...DEFAULT_AVAILABILITY, ...av, blocks: (av.blocks || []).map((b) => ({ id: String(b._id), date: b.date, from: b.from, to: b.to, allDay: b.allDay, reason: b.reason, repeatWeekly: b.repeatWeekly })) };
}

router.get('/availability', async (req, res) => {
  // Open slots for each working day of the current week (for the overview chart).
  const ws = T.weekStart(T.todayStr());
  const week = [];
  for (let i = 0; i < 7; i++) {
    const d = T.addDays(ws, i);
    const slots = await slotsForDate(req.user, d);
    const sched = scheduleForDate(req.user.availability || DEFAULT_AVAILABILITY, d);
    week.push({ date: d, open: slots.filter((s) => s.available).length, working: sched.length > 0 });
  }
  const upcomingBlocks = (req.user.availability?.blocks || []).filter((b) => b.repeatWeekly || b.date >= T.todayStr()).length;
  res.json({ availability: availabilityOut(req.user), week, upcomingBlocks });
});

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:MM');
router.put('/availability', body(z.object({
  workingDays: z.array(z.number().int().min(1).max(7)).max(7).optional(),
  startTime: time.optional(),
  endTime: time.optional(),
  lunchBreak: z.object({ enabled: z.boolean(), start: time, end: time }).optional(),
  sessionLength: z.union([z.literal(30), z.literal(45), z.literal(60)]).optional(),
  bufferMinutes: z.union([z.literal(0), z.literal(5), z.literal(10), z.literal(15)]).optional(),
})), async (req, res) => {
  const cur = availabilityOut(req.user);
  const next = { ...cur, ...req.body };
  if (T.toMinutes(next.startTime) >= T.toMinutes(next.endTime)) throw badRequest('End time must be after start time.', 'VALIDATION_ERROR', { field: 'endTime' });
  if (next.lunchBreak?.enabled && T.toMinutes(next.lunchBreak.start) >= T.toMinutes(next.lunchBreak.end)) throw badRequest('Break must end after it starts.', 'VALIDATION_ERROR', { field: 'lunchBreak' });
  const u = await User.findById(req.user._id);
  u.availability = { ...next, blocks: u.availability?.blocks || [] };
  await u.save();
  res.json({ availability: availabilityOut(u) });
});

router.get('/availability/preview', async (req, res) => {
  const date = String(req.query.date || T.todayStr());
  if (!T.isDateStr(date)) throw badRequest('Invalid date');
  res.json({ date, slots: await slotsForDate(req.user, date) });
});

const blockSchema = z.object({
  date: z.string().refine(T.isDateStr, 'Choose a date'),
  allDay: z.boolean().optional().default(false),
  from: time.optional().default('09:00'),
  to: time.optional().default('10:00'),
  reason: z.string().trim().max(80).optional().default(''),
  repeatWeekly: z.boolean().optional().default(false),
  force: z.boolean().optional().default(false),
});

router.post('/availability/blocks', body(blockSchema), async (req, res) => {
  const b = req.body;
  if (b.date < T.todayStr()) throw badRequest('Choose today or a future date.', 'VALIDATION_ERROR', { field: 'date' });
  if (!b.allDay && T.toMinutes(b.from) >= T.toMinutes(b.to)) throw badRequest('“To” must be after “From”.', 'VALIDATION_ERROR', { field: 'to' });
  const from = T.fromLocal(b.date, b.allDay ? '00:00' : b.from);
  const to = b.allDay ? T.fromLocal(T.addDays(b.date, 1)) : T.fromLocal(b.date, b.to);
  if (!b.force) {
    const Model = req.user.role === 'doctor' ? Consultation : Appointment;
    const who = req.user.role === 'doctor' ? { doctor: req.user._id, status: { $in: ['scheduled'] } } : { counsellor: req.user._id, status: { $in: ACTIVE } };
    const clashes = await Model.find({ ...who, start: { $lt: to }, end: { $gt: from } }).populate('student', 'name');
    if (clashes.length) {
      throw conflict('This overlaps a booked session. Blocking this time won’t cancel it automatically.', 'BLOCK_CONFLICT', {
        conflicts: clashes.map((c) => ({ id: c.id, student: c.student?.name, start: c.start })),
      });
    }
  }
  const u = await User.findById(req.user._id);
  if (!u.availability) u.availability = {};
  u.availability.blocks.push({ date: b.date, from: b.allDay ? '00:00' : b.from, to: b.allDay ? '23:59' : b.to, allDay: b.allDay, reason: b.reason, repeatWeekly: b.repeatWeekly });
  await u.save();
  res.status(201).json({ availability: availabilityOut(u) });
});

router.delete('/availability/blocks/:blockId', async (req, res) => {
  const u = await User.findById(req.user._id);
  const blk = u.availability?.blocks?.id(req.params.blockId);
  if (!blk) throw notFound('Block not found.');
  blk.deleteOne();
  await u.save();
  res.json({ availability: availabilityOut(u) });
});

module.exports = router;
