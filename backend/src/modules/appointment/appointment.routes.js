// MEMBER 1 — Appointment Management (CRUD 1)
// Create appointment, view appointments, reschedule, cancel, update status (accept / decline).
// Counselling-session endpoints on the same URL (/api/appointments/:id/session…) live in
// modules/counselling-session.
const express = require('express');
const crypto = require('crypto');
const Appointment = require('../../models/Appointment');
const User = require('../../models/User');
const { requireAuth, requireRole, requireVerified } = require('../../middleware/auth');
const { body, objectId, z } = require('../../middleware/validate');
const { serialize, POP, loadFor, outFor: out } = require('../../services/appointments');

const T = require('../../utils/time');
const { badRequest, notFound, conflict } = require('../../utils/errors');

const { ACTIVE } = Appointment;
const router = express.Router();
router.use(requireAuth, requireRole('student', 'counsellor'), requireVerified);

const SLOT_MESSAGES = {
  booked: 'That slot was taken a moment ago. Nothing was booked, so it’s safe to try again.',
  past: 'That time has already passed. Please choose a later slot.',
  not_offered: 'That time isn’t available. Please choose one of the listed slots.',
  invalid: 'Choose a valid time.',
};

function activeQuery(studentId) {
  return { student: studentId, status: { $in: ACTIVE }, end: { $gt: new Date() } };
}

async function saveHandlingSlotRace(doc) {
  try {
    await doc.save();
  } catch (e) {
    if (e?.code === 11000) throw conflict(SLOT_MESSAGES.booked, 'SLOT_TAKEN');
    throw e;
  }
}

// ---------- Listing ----------
router.get('/', async (req, res) => {
  const scope = String(req.query.scope || 'upcoming');
  const me = req.user._id;
  const now = new Date();
  const who = req.user.role === 'student' ? { student: me } : { counsellor: me };
  let q; let sort = { start: 1 };
  switch (scope) {
    case 'upcoming': q = { ...who, status: { $in: ACTIVE }, end: { $gt: now } }; break;
    case 'past': q = { ...who, $or: [{ status: { $nin: ACTIVE } }, { end: { $lte: now } }] }; sort = { start: -1 }; break;
    case 'requests': q = { ...who, status: { $in: ['pending', 'reschedule_requested'] }, end: { $gt: now } }; sort = { createdAt: 1 }; break;
    case 'today': {
      const d = T.todayStr();
      q = { ...who, status: { $in: [...ACTIVE, 'completed'] }, start: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 1)) } };
      break;
    }
    case 'date': {
      const d = String(req.query.date || '');
      if (!T.isDateStr(d)) throw badRequest('Choose a valid date');
      q = { ...who, status: { $in: [...ACTIVE, 'completed'] }, start: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 1)) } };
      break;
    }
    default: throw badRequest('Unknown scope');
  }
  const list = await Appointment.find(q).sort(sort).limit(100).populate(POP);
  res.json({ appointments: list.map((a) => out(req, a)) });
});


// ---------- Booking (FR2, FR3, FR7) ----------
const createSchema = z.object({
  counsellorId: objectId,
  start: z.string().datetime({ offset: true }),
  mode: z.enum(['online', 'in_person']),
  note: z.string().trim().max(1000).optional().default(''),
});

  const counsellor = await User.findOne({ _id: counsellorId, role: 'counsellor', status: 'active', 'verification.status': 'approved' });
  if (!counsellor) throw notFound('This counsellor is not available for booking.');
  if (!(counsellor.professional?.modes || ['online', 'in_person']).includes(mode)) throw badRequest('This counsellor doesn’t offer that meeting type.');

  // FR7: one active booking per student. Checked before anything is reserved.
  const existing = await Appointment.find(activeQuery(req.user._id)).populate(POP);
  if (existing.length && settings.appointments.blockDuplicateBookings) {
    throw conflict('You already have an active booking. Reschedule it instead of booking twice.', 'DUPLICATE_BOOKING', { existing: out(req, existing[0]) });
  }


  await notify(counsellor, {
    type: 'booking_request', title: 'New booking request',
    body: `${req.user.name} · ${T.fmtDateTime(a.start)}`, icon: 'inbox', tone: 'amber', link: { screen: 'request', id: a.id },
  });
  if (existing.length) {
    for (const e of existing) {
      await Appointment.updateOne({ _id: e._id }, { $addToSet: { duplicateOf: a._id }, $set: { flaggedDuplicate: true } });
      await notify(e.counsellor, { type: 'duplicate', title: 'Possible duplicate booking', body: `${req.user.name} has ${existing.length + 1} active requests`, icon: 'content_copy', tone: 'red', link: { screen: 'request', id: e.id } });
    }
    await notify(counsellor, { type: 'duplicate', title: 'Possible duplicate booking', body: `${req.user.name} has ${existing.length + 1} active requests`, icon: 'content_copy', tone: 'red', link: { screen: 'request', id: a.id } });
  }
  res.status(201).json({ appointment: out(req, a) });
});



const declineSchema = z.object({
  reason: z.string().trim().min(1, 'Choose a reason').max(120),
  message: z.string().trim().max(1000).optional().default(''),
  suggestSlots: z.boolean().optional().default(true),
});

router.post('/:id/decline', requireRole('counsellor'), body(declineSchema), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.status === 'reschedule_requested') {
    // Declining a reschedule keeps the original confirmed booking.
    a.status = 'confirmed';
    a.history.push({ status: 'confirmed', label: 'Reschedule declined — original time kept', by: 'counsellor' });
    a.proposal = undefined;
    await a.save();
    await notify(a.student, { type: 'reschedule', title: 'Reschedule not possible', body: `${req.body.message || 'Your original time is kept.'}`, icon: 'update', tone: 'amber', link: { screen: 'appointment', id: a.id } });
    return res.json({ appointment: out(req, a) });
  }
  if (a.status !== 'pending') throw conflict('This request is no longer pending.', 'STATE_CHANGED');
  let suggested = [];
  if (req.body.suggestSlots) {
    const counsellor = await User.findById(a.counsellor._id);
    for (let i = 0; i < 21 && suggested.length < 3; i++) {
      const slots = await slotsForDate(counsellor, T.addDays(T.todayStr(), i), { excludeId: a._id });
      for (const s of slots) if (s.available && new Date(s.start).getTime() !== a.start.getTime() && suggested.length < 3) suggested.push(new Date(s.start));
    }
  }
 
});

router.get('/:id/duplicates', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  const others = await Appointment.find({ ...activeQuery(a.student._id), _id: { $ne: a._id } }).populate(POP);
  // Only booking facts are revealed — never notes or check-ins.
  res.json({
    appointment: out(req, a),
    others: others.map((o) => ({ id: o.id, counsellor: { name: o.counsellor.name, initials: o.counsellor.initials }, start: o.start, mode: o.mode, statusLabel: serialize(o, 'admin').statusLabel, statusTone: serialize(o, 'admin').statusTone, isMine: o.counsellor._id.equals(req.user._id) })),
  });
});

router.post('/:id/ask-student', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  await notify(a.student, { type: 'booking', title: 'Please choose one booking', body: `${req.user.name} noticed you have more than one active booking. Keep the one you want and cancel the other so the slot can go to another student.`, icon: 'content_copy', tone: 'amber', link: { screen: 'appointments' } });
  res.json({ sent: true });
});


// ---------- Cancel ----------
router.post('/:id/cancel', body(z.object({ reason: z.string().trim().max(500).optional().default('') })), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (!ACTIVE.includes(a.status)) throw conflict('This booking is no longer active.', 'STATE_CHANGED');
  const isStudent = req.user.role === 'student';
  if (isStudent && a.status !== 'pending') {
    const { appointments } = await getSettings();
    if (a.start.getTime() - Date.now() < appointments.minCancelNoticeHours * 3600 * 1000) {
      throw badRequest(`Bookings can’t be cancelled less than ${appointments.minCancelNoticeHours} hours before. Please contact your counsellor.`, 'TOO_LATE_TO_CANCEL');
    }
  }
  if (!isStudent && !req.body.reason) throw badRequest('Please include a reason for the student.', 'VALIDATION_ERROR', { field: 'reason' });
  a.status = 'cancelled';
  a.slotLock = false;
  a.proposal = undefined;
  a.cancel = { reason: req.body.reason, by: req.user.role, at: new Date() };
  a.history.push({ status: 'cancelled', label: 'Cancelled', by: req.user.role });
  await a.save();
  await notify(isStudent ? a.counsellor : a.student, {
    type: 'cancel', title: isStudent ? 'Booking cancelled by student' : 'Session cancelled',
    body: `${T.fmtDateTime(a.start)}${req.body.reason ? ` — “${req.body.reason}”` : ''}`, icon: 'event_busy', tone: 'red', link: { screen: 'appointment', id: a.id },
  });
  res.json({ appointment: out(req, a) });
});

module.exports = router;
