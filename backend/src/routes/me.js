const express = require('express');
const User = require('../models/User');
const Appointment = require('../models/Appointment');
const M = require('../models');
const { requireAuth } = require('../middleware/auth');
const { body, password, z } = require('../middleware/validate');
const { audit, notify } = require('../services/notify');
const { badRequest, unauthorized } = require('../utils/errors');

// Credential documents and resubmission are in modules/counsellor-approval/application.routes.js.
const router = express.Router();
router.use(requireAuth);

router.get('/', (req, res) => res.json({ user: req.user.toPublic() }));

const phone = z.string().trim().regex(/^\+?[\d\s-]{7,20}$/, 'Enter a valid phone number').or(z.literal(''));

router.patch('/', body(z.object({
  name: z.string().trim().min(2).max(80).optional(),
  preferredName: z.string().trim().max(40).optional(),
  phone: phone.optional(),
  language: z.enum(['English', 'Sinhala', 'Tamil']).optional(),
  gender: z.enum(['female', 'male', 'other', '']).optional(),
  year: z.number().int().min(1).max(6).optional(),
  professional: z.object({
    title: z.string().trim().max(80).optional(),
    qualifications: z.string().trim().max(400).optional(),
    about: z.string().trim().max(1500).optional(),
    focusAreas: z.array(z.string().trim().max(40)).max(12).optional(),
    languages: z.array(z.enum(['English', 'Sinhala', 'Tamil'])).max(3).optional(),
    experienceYears: z.number().int().min(0).max(60).optional(),
    modes: z.array(z.enum(['online', 'in_person'])).min(1).max(2).optional(),
    room: z.string().trim().max(80).optional(),
    office: z.string().trim().max(80).optional(),
    extension: z.string().trim().max(10).optional(),
  }).optional(),
})), async (req, res) => {
  const u = await User.findById(req.user._id);
  const { professional, ...rest } = req.body;
  Object.assign(u, rest);
  if (professional && u.role !== 'student') {
    // Registration numbers are verified credentials and can only change through re-verification.
    u.professional = { ...(u.professional?.toObject?.() || u.professional || {}), ...professional };
  }
  await u.save();
  res.json({ user: u.toPublic() });
});

router.post('/password', body(z.object({ current: z.string().min(1, 'Enter your current password'), next: password })), async (req, res) => {
  const u = await User.findById(req.user._id).select('+passwordHash');
  if (!(await u.checkPassword(req.body.current))) throw badRequest('Your current password isn’t right.', 'WRONG_PASSWORD', { field: 'current' });
  if (req.body.current === req.body.next) throw badRequest('Choose a password you haven’t used here before.', 'VALIDATION_ERROR', { field: 'next' });
  await u.setPassword(req.body.next);
  await u.save();
  // Sign out every other device and turn off quick unlock everywhere (the app sets it up
  // again on this phone if it was on).
  await M.AuthSession.updateMany({ user: u._id, _id: { $ne: req.session._id } }, { revoked: true });
  await M.QuickUnlockKey.deleteMany({ user: u._id });
  await User.updateOne({ _id: u._id }, { 'privacy.biometricUnlock': false });
  res.json({ updated: true });
});

router.patch('/privacy', body(z.object({
  shareMoodTrends: z.boolean().optional(),
  biometricUnlock: z.boolean().optional(),
  hidePreviews: z.boolean().optional(),
})), async (req, res) => {
  const u = await User.findById(req.user._id);
  u.privacy = { ...(u.privacy?.toObject?.() || {}), ...req.body };
  await u.save();
  res.json({ user: u.toPublic() });
});

router.patch('/notification-prefs', body(z.record(z.string().max(40), z.boolean())), async (req, res) => {
  const u = await User.findById(req.user._id);
  for (const [k, v] of Object.entries(req.body)) u.notificationPrefs.set(k, v);
  await u.save();
  res.json({ user: u.toPublic() });
});

// Active sign-ins for this account (shown in security settings).
router.get('/sessions', async (req, res) => {
  const list = await M.AuthSession.find({ user: req.user._id, revoked: false, expiresAt: { $gt: new Date() } }).sort({ lastSeenAt: -1 }).lean();
  res.json({ sessions: list.map((s) => ({ id: s._id.toString(), device: s.device, lastSeenAt: s.lastSeenAt, current: s._id.equals(req.session._id) })) });
});

router.delete('/sessions/:id', async (req, res) => {
  await M.AuthSession.updateOne({ _id: req.params.id, user: req.user._id }, { revoked: true });
  res.json({ revoked: true });
});

// NFR1 — students can download everything MindBridge holds about them.
router.get('/export', async (req, res) => {
  const me = req.user._id;
  const [appointments, moods, journal, chats] = await Promise.all([
    Appointment.find({ student: me }).populate('counsellor', 'name').lean(),
    M.MoodEntry.find({ student: me }).lean(),
    M.JournalEntry.find({ student: me }).lean(),
    M.ChatMessage.find({ student: me }).lean(),
  ]);
  const dec = require('../utils/crypto').decrypt;
  res.setHeader('Content-Disposition', 'attachment; filename="mindbridge-my-data.json"');
  res.json({
    exportedAt: new Date(),
    account: req.user.toPublic(),
    appointments: appointments.map((a) => ({ reference: a.reference, counsellor: a.counsellor?.name, start: a.start, mode: a.mode, status: a.status, note: dec(a.note) })),
    moodCheckins: moods.map((m) => ({ date: m.date, mood: m.mood, factors: m.factors, note: dec(m.note) })),
    journal: journal.map((j) => ({ title: dec(j.title), body: dec(j.body), mood: j.mood, tags: j.tags, createdAt: j.createdAt })),
    bridgeChats: chats.map((c) => ({ from: c.from, text: dec(c.text), at: c.createdAt })),
  });
});

router.delete('/', body(z.object({ password: z.string().min(1, 'Enter your password to confirm') })), async (req, res) => {
  const u = await User.findById(req.user._id).select('+passwordHash');
  if (!(await u.checkPassword(req.body.password))) throw unauthorized('That password isn’t right.', 'WRONG_PASSWORD');
  if (u.role !== 'student') throw badRequest('Staff accounts are closed by Student Affairs.', 'STAFF_ACCOUNT');
  const active = await Appointment.find({ student: u._id, status: { $in: Appointment.ACTIVE } });
  for (const a of active) {
    a.status = 'cancelled'; a.slotLock = false; a.cancel = { reason: 'Account deleted', by: 'student', at: new Date() };
    a.history.push({ status: 'cancelled', label: 'Cancelled', by: 'student' });
    await a.save();
    await notify(a.counsellor, { type: 'cancel', title: 'Booking cancelled by student', body: 'The student closed their account.', icon: 'event_busy', tone: 'red' });
  }
  await Promise.all([
    M.MoodEntry.deleteMany({ student: u._id }), M.JournalEntry.deleteMany({ student: u._id }),
    M.ChatMessage.deleteMany({ student: u._id }), M.Notification.deleteMany({ user: u._id }),
    M.AuthSession.deleteMany({ user: u._id }), M.QuickUnlockKey.deleteMany({ user: u._id }),
  ]);
  await audit(null, 'users', 'Student account deleted by owner', u.studentId || '');
  await u.deleteOne();
  res.json({ deleted: true });
});

module.exports = router;
