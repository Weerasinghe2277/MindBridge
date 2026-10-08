// MEMBER 3 — Counselling Session Management (CRUD 2)
// Create session record (start), view session, update session status/details (checklist, notes),
// complete session. Mounted on /api/appointments because a session belongs to a booking.
const express = require('express');
const Appointment = require('../../models/Appointment');
const User = require('../../models/User');
const SessionNote = require('./session-note.model');
const { MoodEntry } = require('../../models');
const { requireAuth, requireRole, requireVerified } = require('../../middleware/auth');
const { body, z } = require('../../middleware/validate');
const { loadFor, outFor: out, anonymousStudent } = require('../../services/appointments');
const { notify } = require('../../services/notify');
const T = require('../../utils/time');
const { conflict } = require('../../utils/errors');

const { ACTIVE } = Appointment;
// A known student's history with this counsellor never includes their anonymous bookings.
const named = { anonymous: { $ne: true } };
const router = express.Router();
router.use(requireAuth, requireRole('student', 'counsellor'), requireVerified);

// ---------- Sessions (counsellor) ----------
router.post('/:id/session/start', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.status !== 'confirmed') throw conflict('Only confirmed sessions can be started.', 'STATE_CHANGED');
  if (!a.session?.startedAt) {
    a.session = { startedAt: new Date(), checklist: [{ label: 'Confidentiality explained', done: false }, { label: 'Consent recorded', done: false }, { label: 'Agree next steps', done: false }] };
    await a.save();
  }
  res.json({ appointment: out(req, a) });
});

router.patch('/:id/session', requireRole('counsellor'), body(z.object({ checklist: z.array(z.object({ label: z.string().max(80), done: z.boolean() })).max(10) })), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (!a.session?.startedAt) throw conflict('Start the session first.', 'STATE_CHANGED');
  a.session.checklist = req.body.checklist;
  a.markModified('session');
  await a.save();
  res.json({ appointment: out(req, a) });
});

router.post('/:id/complete', requireRole('counsellor'), body(z.object({ noShow: z.boolean().optional().default(false) })), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.status !== 'confirmed') throw conflict('Only confirmed sessions can be completed.', 'STATE_CHANGED');
  a.status = req.body.noShow ? 'no_show' : 'completed';
  if (!a.session?.startedAt) a.session = { startedAt: a.start, checklist: [] };
  a.session.endedAt = new Date();
  a.markModified('session');
  a.history.push({ status: a.status, label: req.body.noShow ? 'Student did not attend' : 'Session completed', by: 'counsellor' });
  await a.save();
  const count = a.anonymous ? null : await Appointment.countDocuments({ student: a.student._id, counsellor: a.counsellor._id, status: 'completed', ...named });
  if (!req.body.noShow) {
    await notify(a.student, { type: 'booking', title: 'Session completed', body: `Thanks for meeting with ${req.user.name}. You can book a follow-up any time.`, icon: 'task_alt', tone: 'green', link: { screen: 'appointment', id: a.id } });
  }
  res.json({ appointment: out(req, a), sessionsTogether: count });
});

// Session notes — encrypted, readable only by the counsellor who wrote them (NFR2).
router.get('/:id/notes', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  const note = await SessionNote.findOne({ appointment: a._id, counsellor: req.user._id });
  const prev = a.anonymous ? null : await SessionNote.findOne({ student: a.student._id, counsellor: req.user._id, appointment: { $ne: a._id }, ...named }).sort({ createdAt: -1 });
  const ser = (n) => n && { summary: n.summary || '', plan: n.plan || '', tags: n.tags, goals: n.goals, recommendReferral: n.recommendReferral, updatedAt: n.updatedAt };
  res.json({ note: ser(note), previous: ser(prev) });
});

router.put('/:id/notes', requireRole('counsellor'), body(z.object({
  summary: z.string().max(5000).optional().default(''),
  plan: z.string().max(3000).optional().default(''),
  tags: z.array(z.string().max(40)).max(10).optional().default([]),
  goals: z.array(z.object({ text: z.string().max(200), done: z.boolean() })).max(10).optional(),
  recommendReferral: z.boolean().optional().default(false),
})), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  const note = await SessionNote.findOneAndUpdate(
    { appointment: a._id },
    { $set: { counsellor: req.user._id, student: a.student._id, anonymous: !!a.anonymous, ...req.body } },
    { upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true },
  );
  res.json({ saved: true, updatedAt: note.updatedAt });
});

// Limited student view for counsellors (NFR1): booking facts, plus mood trends only if shared.
router.get('/:id/student', requireRole('counsellor'), async (req, res) => {
  const a = await loadFor(req, req.params.id);
  if (a.anonymous) {
    // Anonymous booking: nothing about the student, their history or their mood.
    return res.json({ student: anonymousStudent(), anonymous: true, sessions: null, prefers: 'online', moodShared: false, moodTrend: null });
  }
  const s = await User.findById(a.student._id);
  const [upcoming, completed] = await Promise.all([
    Appointment.countDocuments({ student: s._id, counsellor: req.user._id, status: { $in: ACTIVE }, end: { $gt: new Date() }, ...named }),
    Appointment.countDocuments({ student: s._id, counsellor: req.user._id, status: 'completed', ...named }),
  ]);
  const lastMode = await Appointment.findOne({ student: s._id, counsellor: req.user._id, ...named }).sort({ createdAt: -1 }).select('mode');
  let moodTrend = null;
  if (s.privacy?.shareMoodTrends) {
    const since = T.addDays(T.todayStr(), -27);
    const entries = await MoodEntry.find({ student: s._id, date: { $gte: since } }).select('mood date').lean();
    const weeks = [0, 1, 2, 3].map((w) => {
      const from = T.addDays(since, w * 7); const to = T.addDays(from, 7);
      const e = entries.filter((x) => x.date >= from && x.date < to);
      return { label: `W${w + 1}`, avg: e.length ? +(e.reduce((t, x) => t + x.mood, 0) / e.length).toFixed(1) : null };
    });
    moodTrend = weeks;
  }
  res.json({
    student: { id: s.id, name: s.name, initials: s.initials, studentId: s.studentId, faculty: s.faculty, year: s.year, language: s.language, phone: s.phone },
    sessions: { upcoming, completed },
    prefers: lastMode?.mode || null,
    moodShared: !!s.privacy?.shareMoodTrends,
    moodTrend,
  });
});

module.exports = router;
