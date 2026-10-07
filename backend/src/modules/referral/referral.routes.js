// MEMBER 4 — Doctor Referral Management (CRUD 2)
// Create referral, view referrals and details, update status/details (accept, decline,
// request / reply info), track referral status.
// Counsellor → Medical Centre referrals. Doctors see only what the counsellor chose to share (NFR1, NFR2).
const express = require('express');
const User = require('../../models/User');
const Appointment = require('../../models/Appointment');
const Referral = require('./referral.model');
const { Consultation } = require('../../models');
const { requireAuth, requireRole, requireVerified } = require('../../middleware/auth');
const { body, objectId, z, isValidId } = require('../../middleware/validate');
const { notify, audit } = require('../../services/notify');
const { nextAvailable, assertSlotFree } = require('../../services/slots');
const T = require('../../utils/time');
const { notFound, badRequest, conflict, forbidden } = require('../../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('counsellor', 'doctor'), requireVerified);

const POP = [
  { path: 'student', select: 'name studentId faculty year phone' },
  { path: 'counsellor', select: 'name professional' },
  { path: 'doctor', select: 'name professional availability' },
  { path: 'consultation', select: 'start status mode room' },
];

const URG = { routine: { label: 'Routine', tone: 'amber' }, priority: { label: 'Priority', tone: 'red' }, urgent: { label: 'Urgent', tone: 'red' } };
const STAT = { new: { label: 'New', tone: 'amber' }, accepted: { label: 'Accepted', tone: 'green' }, declined: { label: 'Declined', tone: 'grey' } };

function out(r, viewer) {
  const isDoctor = viewer === 'doctor';
  return {
    id: r.id,
    urgency: r.urgency, urgencyLabel: URG[r.urgency].label, urgencyTone: URG[r.urgency].tone,
    status: r.status, statusLabel: STAT[r.status].label, statusTone: STAT[r.status].tone,
    reason: r.reason,
    summary: !isDoctor || r.share.summary ? (r.summary || '') : null,
    contact: !isDoctor || r.share.contact ? (r.contact || r.student?.phone || '') : null,
    share: r.share,
    consent: r.consent,
    student: r.student ? { id: r.student.id, name: r.student.name, initials: r.student.initials, studentId: r.student.studentId, faculty: r.student.faculty, year: r.student.year } : null,
    counsellor: r.counsellor ? { id: r.counsellor.id, name: r.counsellor.name, title: r.counsellor.professional?.title } : null,
    doctor: r.doctor ? { id: r.doctor.id, name: r.doctor.name, title: r.doctor.professional?.title, initials: r.doctor.initials } : null,
    decline: r.decline?.reason ? r.decline : null,
    infoRequests: (r.infoRequests || []).map((x, i) => ({ index: i, items: x.items, message: x.message, reply: x.reply || '', at: x.at, repliedAt: x.repliedAt })),
    consultation: r.consultation?.start ? { id: r.consultation.id, start: r.consultation.start, status: r.consultation.status, mode: r.consultation.mode, room: r.consultation.room } : null,
    createdAt: r.createdAt,
  };
}

async function load(req) {
  if (!isValidId(req.params.id)) throw notFound('Referral not found.');
  const r = await Referral.findById(req.params.id).populate(POP);
  if (!r) throw notFound('Referral not found.');
  const me = req.user._id;
  if (!(r.counsellor._id.equals(me) || r.doctor._id.equals(me))) throw notFound('Referral not found.');
  return r;
}

router.get('/', async (req, res) => {
  const who = req.user.role === 'doctor' ? { doctor: req.user._id } : { counsellor: req.user._id };
  const status = String(req.query.status || '');
  const q = { ...who };
  if (['new', 'accepted', 'declined'].includes(status)) q.status = status;
  const list = await Referral.find(q).sort({ createdAt: -1 }).populate(POP);
  const order = { urgent: 0, priority: 1, routine: 2 };
  list.sort((a, b) => (a.status === 'new' && b.status === 'new' ? order[a.urgency] - order[b.urgency] : 0));
  res.json({ referrals: list.map((r) => out(r, req.user.role)) });
});

router.get('/:id', async (req, res) => {
  const r = await load(req);
  // Every doctor view is audited (who opened a record — never what it contains).
  if (req.user.role === 'doctor') await audit(req.user, 'access', 'Referral viewed', `${r.student.name} (${r.student.studentId})`);
  res.json({ referral: out(r, req.user.role) });
});

const createSchema = z.object({
  appointmentId: objectId,
  doctorId: objectId,
  urgency: z.enum(['routine', 'priority', 'urgent']),
  reason: z.string().trim().min(10, 'Describe the reason for referral').max(2000),
  summary: z.string().trim().max(2000).optional().default(''),
  share: z.object({ summary: z.boolean(), contact: z.boolean() }),
  consent: z.boolean(),
});

router.post('/', requireRole('counsellor'), body(createSchema), async (req, res) => {
  const b = req.body;
  if (!b.consent) throw badRequest('Record the student’s consent before referring.', 'CONSENT_REQUIRED', { field: 'consent' });
  const appt = await Appointment.findOne({ _id: b.appointmentId, counsellor: req.user._id }).populate('student');
  if (!appt) throw notFound('Session not found.');
  const doctor = await User.findOne({ _id: b.doctorId, role: 'doctor', status: 'active', 'verification.status': 'approved' });
  if (!doctor) throw notFound('Doctor not found.');
  if (await Referral.findOne({ student: appt.student._id, doctor: doctor._id, status: 'new' })) {
    throw conflict('This student already has an open referral with this doctor.', 'DUPLICATE_REFERRAL');
  }
  const r = await Referral.create({
    counsellor: req.user._id, doctor: doctor._id, student: appt.student._id, appointment: appt._id,
    urgency: b.urgency, reason: b.reason, summary: b.share.summary ? b.summary : '',
    contact: b.share.contact ? (appt.student.phone || '') : '',
    share: { summary: b.share.summary, contact: b.share.contact, fullNotes: false }, consent: true,
  });
  await r.populate(POP);
  await notify(doctor, {
    type: b.urgency === 'urgent' ? 'referral_urgent' : 'referral', title: `${URG[b.urgency].label} referral`, body: `${appt.student.name} · from ${req.user.name}`,
    icon: b.urgency === 'routine' ? 'assignment_ind' : 'priority_high', tone: b.urgency === 'routine' ? 'amber' : 'red', link: { screen: 'referral', id: r.id },
  });
  res.status(201).json({ referral: out(r, 'counsellor') });
});

router.get('/:id/suggest-slot', requireRole('doctor'), async (req, res) => {
  await load(req);
  const doc = await User.findById(req.user._id);
  res.json({ slot: await nextAvailable(doc, { role: 'doctor' }) });
});

router.post('/:id/accept', requireRole('doctor'), body(z.object({
  start: z.string().datetime({ offset: true }),
  mode: z.enum(['online', 'in_person']).optional().default('in_person'),
})), async (req, res) => {
  const r = await load(req);
  if (r.status !== 'new') throw conflict('This referral has already been handled.', 'STATE_CHANGED');
  const doc = await User.findById(req.user._id);
  const check = await assertSlotFree(doc, req.body.start, { role: 'doctor' });
  if (!check.ok) throw conflict('That consultation slot is no longer free. Pick another.', 'SLOT_TAKEN');
  const c = await Consultation.create({
    doctor: doc._id, student: r.student._id, referral: r._id, start: new Date(check.slot.start), end: new Date(check.slot.end),
    mode: req.body.mode, room: req.body.mode === 'in_person' ? (doc.professional?.room || 'Medical Centre') : 'Online',
  });
  r.status = 'accepted';
  r.consultation = c._id;
  await r.save();
  await r.populate(POP);
  const when = T.fmtDateTime(c.start);
  await notify(r.counsellor, { type: 'referral', title: 'Referral accepted', body: `${req.user.name} accepted ${r.student.name}’s referral`, icon: 'local_hospital', tone: 'green', link: { screen: 'referral', id: r.id } });
  await notify(r.student, { type: 'booking', title: 'Medical Centre appointment', body: `${req.user.name} offered ${when} · ${c.room}`, icon: 'local_hospital', tone: 'green' });
  res.json({ referral: out(r, 'doctor'), consultationId: c.id });
});

router.post('/:id/decline', requireRole('doctor'), body(z.object({ reason: z.string().trim().min(1, 'Choose a reason').max(120), note: z.string().trim().max(1000).optional().default('') })), async (req, res) => {
  const r = await load(req);
  if (r.status !== 'new') throw conflict('This referral has already been handled.', 'STATE_CHANGED');
  r.status = 'declined';
  r.decline = { reason: req.body.reason, note: req.body.note };
  await r.save();
  await notify(r.counsellor, { type: 'referral', title: 'Referral declined', body: `${req.user.name}: ${req.body.reason}${req.body.note ? ` — ${req.body.note}` : ''}`, icon: 'assignment_late', tone: 'grey', link: { screen: 'referral', id: r.id } });
  res.json({ referral: out(r, 'doctor') });
});

router.post('/:id/request-info', requireRole('doctor'), body(z.object({ items: z.array(z.string().max(40)).max(6).default([]), message: z.string().trim().min(1, 'Add a short message').max(1000) })), async (req, res) => {
  const r = await load(req);
  r.infoRequests.push({ items: req.body.items, message: req.body.message, at: new Date() });
  await r.save();
  await notify(r.counsellor, { type: 'referral', title: 'Doctor asked for more information', body: `${r.student.name}: ${req.body.message}`, icon: 'help', tone: 'blue', link: { screen: 'referral', id: r.id } });
  res.json({ referral: out(r, 'doctor') });
});

router.post('/:id/reply-info', requireRole('counsellor'), body(z.object({ index: z.number().int().min(0), reply: z.string().trim().min(1).max(2000) })), async (req, res) => {
  const r = await load(req);
  const item = r.infoRequests[req.body.index];
  if (!item) throw notFound('Request not found.');
  if (!r.counsellor._id.equals(req.user._id)) throw forbidden();
  item.reply = req.body.reply;
  item.repliedAt = new Date();
  await r.save();
  await notify(r.doctor, { type: 'referral', title: 'Counsellor replied', body: `${r.student.name}: details added`, icon: 'reply', tone: 'green', link: { screen: 'referral', id: r.id } });
  res.json({ referral: out(r, 'counsellor') });
});

module.exports = router;
