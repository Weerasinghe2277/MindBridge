// University Medical Centre workspace: consultations, follow-ups and referred students.
const express = require('express');
const User = require('../models/User');
const { Referral, Consultation } = require('../models');
const { requireAuth, requireRole, requireVerified } = require('../middleware/auth');
const { body, z, isValidId } = require('../middleware/validate');
const { notify } = require('../services/notify');
const { slotsForDate, monthOverview, assertSlotFree } = require('../services/slots');
const T = require('../utils/time');
const { notFound, badRequest, conflict } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('doctor'), requireVerified);

const POP = [
  { path: 'student', select: 'name studentId faculty year createdAt' },
  { path: 'referral', select: 'reason summary share counsellor urgency createdAt', populate: { path: 'counsellor', select: 'name' } },
];

const STATUS = { scheduled: ['Scheduled', 'blue'], in_progress: ['In progress', 'amber'], completed: ['Completed', 'grey'], cancelled: ['Cancelled', 'red'] };

function out(c, full = false) {
  const today = T.todayStr();
  const ds = T.local(c.start).dateStr;
  const o = {
    id: c.id, start: c.start, end: c.end, mode: c.mode, room: c.room, status: c.status,
    statusLabel: STATUS[c.status][0], statusTone: STATUS[c.status][1],
    dayLabel: ds === today ? 'Today' : ds === T.addDays(today, 1) ? 'Tomorrow' : null,
    student: c.student ? { id: c.student.id, name: c.student.name, initials: c.student.initials, studentId: c.student.studentId, faculty: c.student.faculty, year: c.student.year } : null,
    referral: c.referral ? {
      id: c.referral.id, reason: c.referral.reason, urgency: c.referral.urgency,
      summary: c.referral.share?.summary ? c.referral.summary : null,
      counsellor: c.referral.counsellor?.name,
    } : null,
    isFollowUp: !!c.followUpOf,
    startedAt: c.startedAt, endedAt: c.endedAt,
  };
  if (full) Object.assign(o, { vitals: c.vitals || {}, assessment: c.assessment || '', tags: c.tags || [], clinicalNotes: c.clinicalNotes || '', plan: c.plan || '', shareSummary: c.shareSummary });
  return o;
}

async function load(req) {
  if (!isValidId(req.params.id)) throw notFound('Consultation not found.');
  const c = await Consultation.findOne({ _id: req.params.id, doctor: req.user._id }).populate(POP);
  if (!c) throw notFound('Consultation not found.');
  return c;
}

router.get('/dashboard', async (req, res) => {
  const d = T.todayStr();
  const [newRefs, today, followUps] = await Promise.all([
    Referral.find({ doctor: req.user._id, status: 'new' }).populate('student', 'name').populate('counsellor', 'name').sort({ createdAt: -1 }),
    Consultation.find({ doctor: req.user._id, status: { $in: ['scheduled', 'in_progress'] }, start: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 1)) } }).sort({ start: 1 }).populate(POP),
    Consultation.find({ doctor: req.user._id, status: 'scheduled', followUpOf: { $exists: true }, start: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 8)) } }).sort({ start: 1 }).populate(POP),
  ]);
  const priority = newRefs.find((r) => r.urgency !== 'routine');
  res.json({
    newReferrals: newRefs.length,
    todayCount: today.length,
    priority: priority ? { id: priority.id, student: priority.student.name, counsellor: priority.counsellor.name, urgency: priority.urgency } : null,
    today: today.map((c) => out(c)),
    followUps: followUps.map((c) => out(c)),
  });
});

router.get('/consultations', async (req, res) => {
  const scope = String(req.query.scope || 'today');
  const d = T.todayStr();
  let q; let sort = { start: 1 };
  if (scope === 'today') q = { status: { $in: ['scheduled', 'in_progress', 'completed'] }, start: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 1)) } };
  else if (scope === 'upcoming') q = { status: 'scheduled', start: { $gte: T.fromLocal(T.addDays(d, 1)) } };
  else if (scope === 'completed') { q = { status: 'completed' }; sort = { start: -1 }; } else throw badRequest('Unknown scope');
  const list = await Consultation.find({ doctor: req.user._id, ...q }).sort(sort).limit(100).populate(POP);
  res.json({ consultations: list.map((c) => out(c)) });
});

router.get('/consultations/:id', async (req, res) => {
  const c = await load(req);
  res.json({ consultation: out(c, true) });
});

router.post('/consultations/:id/start', async (req, res) => {
  const c = await load(req);
  if (c.status === 'scheduled') { c.status = 'in_progress'; c.startedAt = new Date(); await c.save(); }
  res.json({ consultation: out(c, true) });
});

router.put('/consultations/:id', body(z.object({
  vitals: z.object({ bloodPressure: z.string().max(20).optional(), avgSleep: z.string().max(20).optional() }).optional(),
  assessment: z.string().max(5000).optional(),
  tags: z.array(z.string().max(40)).max(10).optional(),
  clinicalNotes: z.string().max(5000).optional(),
  plan: z.string().max(2000).optional(),
  shareSummary: z.boolean().optional(),
})), async (req, res) => {
  const c = await load(req);
  if (c.status === 'cancelled') throw conflict('This consultation was cancelled.');
  Object.assign(c, req.body);
  await c.save();
  res.json({ consultation: out(c, true) });
});

router.post('/consultations/:id/complete', async (req, res) => {
  const c = await load(req);
  if (!['scheduled', 'in_progress'].includes(c.status)) throw conflict('This consultation is already closed.');
  c.status = 'completed';
  if (!c.startedAt) c.startedAt = c.start;
  c.endedAt = new Date();
  await c.save();
  const ref = c.referral ? await Referral.findById(c.referral._id).populate('counsellor') : null;
  if (ref && c.shareSummary) {
    // Only the plan is shared back — clinical notes stay with the Medical Centre.
    await notify(ref.counsellor, { type: 'referral', title: 'Consultation summary', body: `${c.student.name}: ${c.plan || 'Consultation completed.'}`, icon: 'local_hospital', tone: 'green', link: { screen: 'referral', id: ref.id } });
  }
  res.json({ consultation: out(c, true), durationMin: Math.max(1, Math.round((c.endedAt - c.startedAt) / 60000)) });
});

router.get('/slots', async (req, res) => {
  const date = String(req.query.date || '');
  if (!T.isDateStr(date)) throw badRequest('Choose a valid date');
  res.json({ date, slots: await slotsForDate(req.user, date, { role: 'doctor' }) });
});

router.get('/month', async (req, res) => {
  const month = String(req.query.month || T.todayStr().slice(0, 7));
  if (!/^\d{4}-\d{2}$/.test(month)) throw badRequest('Invalid month');
  res.json({ month, days: await monthOverview(req.user, month, { role: 'doctor' }) });
});

router.post('/consultations/:id/follow-up', body(z.object({
  start: z.string().datetime({ offset: true }),
  mode: z.enum(['online', 'in_person']),
  notifyCounsellor: z.boolean().optional().default(true),
})), async (req, res) => {
  const prev = await load(req);
  const check = await assertSlotFree(req.user, req.body.start, { role: 'doctor' });
  if (!check.ok) throw conflict('That slot is no longer free. Pick another.', 'SLOT_TAKEN');
  const c = await Consultation.create({
    doctor: req.user._id, student: prev.student._id, referral: prev.referral?._id, followUpOf: prev._id,
    start: new Date(check.slot.start), end: new Date(check.slot.end), mode: req.body.mode,
    room: req.body.mode === 'in_person' ? (req.user.professional?.room || 'Medical Centre') : 'Online',
  });
  await notify(prev.student, { type: 'booking', title: 'Follow-up scheduled', body: `${req.user.name} · ${T.fmtDateTime(c.start)}`, icon: 'local_hospital', tone: 'green' });
  if (req.body.notifyCounsellor && prev.referral) {
    const ref = await Referral.findById(prev.referral._id).populate('counsellor');
    await notify(ref.counsellor, { type: 'referral', title: 'Follow-up scheduled', body: `${prev.student.name} · ${T.fmtDateTime(c.start)}`, icon: 'local_hospital', tone: 'blue', link: { screen: 'referral', id: ref.id } });
  }
  await c.populate(POP);
  res.status(201).json({ consultation: out(c) });
});

// Only students referred to this doctor are visible here.
router.get('/students', async (req, res) => {
  const refs = await Referral.find({ doctor: req.user._id, status: { $ne: 'declined' } }).populate('student', 'name studentId faculty year');
  const q = String(req.query.q || '').toLowerCase();
  const map = new Map();
  for (const r of refs) if (r.student && !map.has(r.student.id)) map.set(r.student.id, r.student);
  const out2 = [];
  for (const s of map.values()) {
    if (q && !`${s.name} ${s.studentId}`.toLowerCase().includes(q)) continue;
    const last = await Consultation.findOne({ doctor: req.user._id, student: s._id, status: 'completed' }).sort({ start: -1 });
    const nextFu = await Consultation.findOne({ doctor: req.user._id, student: s._id, status: 'scheduled' }).sort({ start: 1 });
    out2.push({
      id: s.id, name: s.name, initials: s.initials, studentId: s.studentId,
      lastSeen: last?.start || null, nextVisit: nextFu?.start || null,
      followUpDue: !!(nextFu && nextFu.followUpOf),
    });
  }
  res.json({ students: out2 });
});

router.get('/students/:id', async (req, res) => {
  if (!isValidId(req.params.id)) throw notFound();
  const refs = await Referral.find({ doctor: req.user._id, student: req.params.id }).populate('counsellor', 'name').sort({ createdAt: -1 });
  if (!refs.length) throw notFound('Student not found.');
  const s = await User.findById(req.params.id).select('name studentId faculty year');
  const cons = await Consultation.find({ doctor: req.user._id, student: s._id }).sort({ start: -1 });
  res.json({
    student: { id: s.id, name: s.name, initials: s.initials, studentId: s.studentId, faculty: s.faculty, year: s.year },
    referrals: refs.map((r) => ({ id: r.id, createdAt: r.createdAt, counsellor: r.counsellor.name, status: r.status })),
    consultations: cons.map((c) => ({ id: c.id, start: c.start, status: c.status, tags: c.tags, isFollowUp: !!c.followUpOf })),
    latestConsultationId: cons[0]?.id || null,
  });
});

module.exports = router;
