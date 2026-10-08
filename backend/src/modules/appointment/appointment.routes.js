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
const { serialize, studentName, POP, loadFor, outFor: out } = require('../../services/appointments');
const { assertSlotFree, slotsForDate } = require('../../services/slots');
const { getSettings } = require('../../services/settings');
const { notify } = require('../../services/notify');
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

// FR7 — lets the booking flow show "No other active booking" before submit.
router.get('/active-check', requireRole('student'), async (req, res) => {
  const existing = await Appointment.findOne(activeQuery(req.user._id)).populate(POP);
  const settings = await getSettings();
  res.json({ existing: existing ? out(req, existing) : null, blocking: settings.appointments.blockDuplicateBookings });
});

router.get('/:id', async (req, res) => {
  const a = await loadFor(req, req.params.id);
  res.json({ appointment: out(req, a) });
});

// ---------- Booking (FR2, FR3, FR7) ----------
const createSchema = z.object({
  counsellorId: objectId,
  start: z.string().datetime({ offset: true }),
  mode: z.enum(['online', 'in_person']),
  note: z.string().trim().max(1000).optional().default(''),
  anonymous: z.boolean().optional().default(false),
});

router.post('/', requireRole('student'), body(createSchema), async (req, res) => {
  const { counsellorId, start, mode, note, anonymous } = req.body;
  if (anonymous && mode !== 'online') throw badRequest('Anonymous booking is only available for online sessions.', 'VALIDATION_ERROR', { field: 'anonymous' });
  const settings = await getSettings();
  if (mode === 'online' && !settings.appointments.allowOnline) throw badRequest('Online sessions are not available right now.');
  if (mode === 'in_person' && !settings.appointments.allowInPerson) throw badRequest('In-person sessions are not available right now.');

  const counsellor = await User.findOne({ _id: counsellorId, role: 'counsellor', status: 'active', 'verification.status': 'approved' });
  if (!counsellor) throw notFound('This counsellor is not available for booking.');
  if (!(counsellor.professional?.modes || ['online', 'in_person']).includes(mode)) throw badRequest('This counsellor doesn’t offer that meeting type.');

  // FR7: one active booking per student. Checked before anything is reserved.
  const existing = await Appointment.find(activeQuery(req.user._id)).populate(POP);
  if (existing.length && settings.appointments.blockDuplicateBookings) {
    throw conflict('You already have an active booking. Reschedule it instead of booking twice.', 'DUPLICATE_BOOKING', { existing: out(req, existing[0]) });
  }

  const check = await assertSlotFree(counsellor, start);
  if (!check.ok) throw conflict(SLOT_MESSAGES[check.reason] || SLOT_MESSAGES.booked, 'SLOT_TAKEN');
  const linkable = anonymous ? [] : existing.filter((e) => !e.anonymous);

  const a = new Appointment({
    student: req.user._id,
    counsellor: counsellor._id,
    start: new Date(check.slot.start),
    end: new Date(check.slot.end),
    mode,
    anonymous,
    location: mode === 'in_person' ? (counsellor.professional?.room || 'Wellbeing Centre, Room 2.14, Main Building') : 'Online',
    note,
    // Anonymous bookings are never linked to the student's other bookings (that would reveal who it is).
    duplicateOf: linkable.map((e) => e._id),
    flaggedDuplicate: linkable.length > 0,
    history: [{ status: 'pending', label: 'Request sent', by: 'student' }],
  });
  await saveHandlingSlotRace(a);
  await a.populate(POP);

  await notify(counsellor, {
    type: 'booking_request', title: 'New booking request',
    body: `${studentName(a)} · ${T.fmtDateTime(a.start)}${anonymous ? ' · online' : ''}`, icon: 'inbox', tone: 'amber', link: { screen: 'request', id: a.id },
  });
  if (linkable.length) {
    for (const e of linkable) {
      await Appointment.updateOne({ _id: e._id }, { $addToSet: { duplicateOf: a._id }, $set: { flaggedDuplicate: true } });
      await notify(e.counsellor, { type: 'duplicate', title: 'Possible duplicate booking', body: `${req.user.name} has ${linkable.length + 1} active requests`, icon: 'content_copy', tone: 'red', link: { screen: 'request', id: e.id } });
    }
    await notify(counsellor, { type: 'duplicate', title: 'Possible duplicate booking', body: `${req.user.name} has ${linkable.length + 1} active requests`, icon: 'content_copy', tone: 'red', link: { screen: 'request', id: a.id } });
  }
  res.status(201).json({ appointment: out(req, a) });
});

// ---------- Counsellor decisions (FR6) ----------
function meetingLinkFor(a) {
  return `https://meet.jit.si/MindBridge-${a.reference}-${crypto.randomBytes(4).toString('hex')}`;
}

router.post('/:id/accept', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.status === 'pending') {
    if (a.start <= new Date()) throw conflict('This request’s time has already passed.', 'EXPIRED');
    a.status = 'confirmed';
    if (a.mode === 'online' && !a.meetingLink) a.meetingLink = meetingLinkFor(a);
    a.history.push({ status: 'confirmed', label: 'Confirmed', by: 'counsellor' });
    a.duplicateOf = [];
    await a.save();
    await notify(a.student, { type: 'booking', title: 'Booking confirmed', body: `${req.user.name} confirmed ${T.fmtDateTime(a.start)}.`, icon: 'event_available', tone: 'green', link: { screen: 'appointment', id: a.id } });
  } else if (a.status === 'reschedule_requested') {
    await applyProposal(a, 'counsellor');
    await notify(a.student, { type: 'reschedule', title: 'New time confirmed', body: `${req.user.name} confirmed ${T.fmtDateTime(a.start)}.`, icon: 'update', tone: 'blue', link: { screen: 'appointment', id: a.id } });
  } else {
    throw conflict('Couldn’t accept this request. The student may have cancelled a moment ago.', 'STATE_CHANGED');
  }
  res.json({ appointment: out(req, a) });
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
  a.status = 'declined';
  a.slotLock = false;
  a.decline = { reason: req.body.reason, message: req.body.message, suggestedSlots: suggested };
  a.history.push({ status: 'declined', label: 'Declined', by: 'counsellor' });
  await a.save();
  await notify(a.student, { type: 'booking', title: 'Request declined', body: req.body.message || req.body.reason, icon: 'event_busy', tone: 'red', link: { screen: 'appointment', id: a.id } });
  res.json({ appointment: out(req, a) });
});

router.get('/:id/duplicates', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  // Anonymous bookings are never matched with the student's other bookings, in either direction.
  const others = a.anonymous ? [] : await Appointment.find({ ...activeQuery(a.student._id), _id: { $ne: a._id }, anonymous: { $ne: true } }).populate(POP);
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

// ---------- Reschedule (FR3) ----------
const rescheduleSchema = z.object({
  start: z.string().datetime({ offset: true }),
  reason: z.string().trim().max(500).optional().default(''),
});

async function applyProposal(a, by) {
  const len = a.proposal.end - a.proposal.start;
  a.start = a.proposal.start;
  a.end = new Date(a.proposal.start.getTime() + len);
  a.status = 'confirmed';
  a.remindersSent = { day: false, hour: false };
  if (a.mode === 'online' && !a.meetingLink) a.meetingLink = meetingLinkFor(a);
  a.history.push({ status: 'confirmed', label: 'Rescheduled', by });
  a.proposal = undefined;
  await saveHandlingSlotRace(a);
}

router.post('/:id/reschedule', body(rescheduleSchema), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  const isStudent = req.user.role === 'student';
  if (!['pending', 'confirmed'].includes(a.status)) throw conflict('This booking can’t be rescheduled in its current state.', 'STATE_CHANGED');
  const counsellor = await User.findById(a.counsellor._id);
  const check = await assertSlotFree(counsellor, req.body.start, { excludeId: a._id });
  if (!check.ok) throw conflict(SLOT_MESSAGES[check.reason] || SLOT_MESSAGES.booked, 'SLOT_TAKEN');
  const newStart = new Date(check.slot.start);
  const newEnd = new Date(check.slot.end);
  const other = isStudent ? a.counsellor : a.student;

  if (isStudent && a.status === 'pending') {
    // Not yet confirmed: simply move the request — still one booking, still pending.
    a.start = newStart; a.end = newEnd;
    a.history.push({ status: 'pending_moved', label: 'Time changed by student', by: 'student' });
    await saveHandlingSlotRace(a);
    await notify(other, { type: 'reschedule', title: 'Request time changed', body: `${studentName(a)} moved their request to ${T.fmtDateTime(newStart)}.`, icon: 'update', tone: 'blue', link: { screen: 'request', id: a.id } });
  } else {
    a.proposal = { start: newStart, end: newEnd, reason: req.body.reason, by: isStudent ? 'student' : 'counsellor', at: new Date() };
    a.status = isStudent ? 'reschedule_requested' : 'reschedule_proposed';
    a.history.push({ status: a.status, label: isStudent ? 'Reschedule requested' : 'New time proposed', by: req.user.role });
    await a.save();
    await notify(other, {
      type: 'reschedule',
      title: isStudent ? 'Reschedule requested' : 'New time proposed',
      body: `${isStudent ? studentName(a) : req.user.name}: ${T.fmtDateTime(newStart)}${req.body.reason ? ` — “${req.body.reason}”` : ''}`,
      icon: 'update', tone: 'blue', link: { screen: isStudent ? 'request' : 'appointment', id: a.id },
    });
  }
  res.json({ appointment: out(req, a) });
});

// Student answers a counsellor's proposal.
router.post('/:id/proposal', requireRole('student'), body(z.object({ accept: z.boolean() })), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.status !== 'reschedule_proposed') throw conflict('There’s no pending proposal for this booking.', 'STATE_CHANGED');
  if (req.body.accept) {
    await applyProposal(a, 'student');
    await notify(a.counsellor, { type: 'reschedule', title: 'Reschedule accepted', body: `${studentName(a)} moved to ${T.fmtDateTime(a.start)}`, icon: 'update', tone: 'blue', link: { screen: 'appointment', id: a.id } });
  } else {
    a.status = 'confirmed';
    a.proposal = undefined;
    a.history.push({ status: 'confirmed', label: 'Proposal declined — original time kept', by: 'student' });
    await a.save();
    await notify(a.counsellor, { type: 'reschedule', title: 'Proposal declined', body: `${studentName(a)} kept the original time, ${T.fmtDateTime(a.start)}`, icon: 'update', tone: 'amber', link: { screen: 'appointment', id: a.id } });
  }
  res.json({ appointment: out(req, a) });
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

router.patch('/:id/reminders', requireRole('student'), body(z.object({ on: z.boolean() })), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  a.remindersOn = req.body.on;
  await a.save();
  res.json({ appointment: out(req, a) });
});

module.exports = router;
