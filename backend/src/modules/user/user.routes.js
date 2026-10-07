// MEMBER 2 — User Management (CRUD 1), admin side. Mounted at /api/admin.
// View users, view one user, edit user (role), deactivate / reactivate user, send password reset.
// Sign Up (create) is in signup.routes.js.
const express = require('express');
const User = require('../../models/User');
const Appointment = require('../../models/Appointment');
const { AuthSession } = require('../../models');
const { requireAuth, requireRole } = require('../../middleware/auth');
const { body, z } = require('../../middleware/validate');
const { notify, audit } = require('../../services/notify');
const { createOtp } = require('../../services/otp');
const T = require('../../utils/time');
const { badRequest, conflict } = require('../../utils/errors');
const { ROLE_LABEL, userRow, loadUser } = require('./user.helpers');

const router = express.Router();
router.use(requireAuth, requireRole('admin'));

// ---------- Users & roles ----------
router.get('/users', async (req, res) => {
  const q = {};
  const roles = String(req.query.role || '').split(',').filter((r) => ROLE_LABEL[r]);
  if (roles.length) q.role = { $in: roles };
  const status = String(req.query.status || '');
  if (status === 'active') q.status = 'active';
  if (status === 'deactivated') q.status = 'deactivated';
  if (status === 'pending') q['verification.status'] = { $in: ['pending', 'changes_requested'] };
  const joined = String(req.query.joined || '');
  if (joined === 'month') q.createdAt = { $gte: T.fromLocal(`${T.todayStr().slice(0, 7)}-01`) };
  if (joined === 'year') q.createdAt = { $gte: T.fromLocal(`${T.todayStr().slice(0, 4)}-01-01`) };
  if (req.query.faculty) q.faculty = String(req.query.faculty);
  const s = String(req.query.q || '').trim();
  if (s) {
    const rx = new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    q.$or = [{ name: rx }, { email: rx }, { studentId: rx }];
  }
  const total = await User.countDocuments(q);
  const list = await User.find(q).sort({ createdAt: -1 }).limit(200);
  res.json({ users: list.map(userRow), total });
});


router.get('/users/:id', async (req, res) => {
  const u = await loadUser(req.params.id);
  res.json({ user: { ...userRow(u), phone: u.phone, faculty: u.faculty, year: u.year, lastActiveAt: u.lastActiveAt, professional: u.role !== 'student' ? u.professional : undefined, statusReason: u.statusReason } });
});

router.patch('/users/:id/role', body(z.object({ role: z.enum(['student', 'counsellor', 'doctor', 'admin']) })), async (req, res) => {
  const u = await loadUser(req.params.id);
  if (u._id.equals(req.user._id)) throw badRequest('You can’t change your own role.');
  const from = u.role; const to = req.body.role;
  if (from === to) throw badRequest(`${u.name} is already a ${ROLE_LABEL[to]}.`);
  if (to === 'student' && !u.studentId) throw badRequest('This person has no student ID, so they can’t become a student.');
  const active = await Appointment.countDocuments({ $or: [{ student: u._id }, { counsellor: u._id }], status: { $in: Appointment.ACTIVE } });
  if (active) throw conflict(`${u.name} has ${active} active booking(s). Resolve them before changing role.`, 'HAS_ACTIVE_BOOKINGS');
  u.role = to;
  if (to === 'counsellor' || to === 'doctor') {
    u.professional = u.professional || {};
    if (!u.availability) u.availability = {};
    u.verification = { status: 'pending', submittedAt: new Date(), documents: u.verification?.documents || [], history: [{ label: `Role changed to ${ROLE_LABEL[to]} by Student Affairs`, at: new Date() }] };
  }
  await u.save();
  await AuthSession.updateMany({ user: u._id }, { revoked: true }); // new role takes effect at next sign-in
  await audit(req.user, 'users', 'Role changed', `${u.name}: ${ROLE_LABEL[from]} → ${ROLE_LABEL[to]}`);
  await notify(u, { type: 'account', title: 'Your role changed', body: `You are now a ${ROLE_LABEL[to]}${to === 'counsellor' || to === 'doctor' ? '. Upload your credentials to be verified.' : '.'}`, icon: 'manage_accounts', tone: 'blue' });
  res.json({ user: userRow(u), from: ROLE_LABEL[from], to: ROLE_LABEL[to] });
});

router.patch('/users/:id/status', body(z.object({ status: z.enum(['active', 'deactivated']), reason: z.string().trim().max(300).optional().default('') })), async (req, res) => {
  const u = await loadUser(req.params.id);
  if (u._id.equals(req.user._id)) throw badRequest('You can’t deactivate your own account.');
  if (req.body.status === 'deactivated' && !req.body.reason) throw badRequest('Add a reason. It’s recorded in the activity log.', 'VALIDATION_ERROR', { field: 'reason' });
  u.status = req.body.status;
  u.statusReason = req.body.reason;
  await u.save();
  if (u.status === 'deactivated') {
    await AuthSession.updateMany({ user: u._id }, { revoked: true });
    const active = await Appointment.find({ $or: [{ student: u._id }, { counsellor: u._id }], status: { $in: Appointment.ACTIVE } });
    for (const a of active) {
      a.status = 'cancelled'; a.slotLock = false; a.cancel = { reason: 'Account deactivated', by: 'admin', at: new Date() };
      a.history.push({ status: 'cancelled', label: 'Cancelled by Student Affairs', by: 'admin' });
      await a.save();
      const other = a.student.equals(u._id) ? a.counsellor : a.student;
      await notify(other, { type: 'cancel', title: 'Booking cancelled', body: `Your booking on ${T.fmtDateTime(a.start)} was cancelled by Student Affairs.`, icon: 'event_busy', tone: 'red' });
    }
  }
  await audit(req.user, 'users', u.status === 'active' ? 'Account activated' : 'Account deactivated', `${u.name}${req.body.reason ? ` — ${req.body.reason}` : ''}`);
  res.json({ user: userRow(u) });
});

router.post('/users/:id/password-reset', async (req, res) => {
  const u = await loadUser(req.params.id);
  const dev = await createOtp(u.email, 'reset_password');
  await audit(req.user, 'users', 'Password reset sent', u.name);
  res.json({ sent: true, email: u.email, ...dev });
});

router.get('/roles', async (req, res) => {
  const counts = {};
  for (const r of Object.keys(ROLE_LABEL)) counts[r] = await User.countDocuments({ role: r });
  res.json({ counts });
});

module.exports = router;
