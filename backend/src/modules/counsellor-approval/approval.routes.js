// MEMBER 2 — Counsellor Approval (CRUD 2), admin side. Mounted at /api/admin.
// View pending counsellors/doctors, view an application, tick documents, approve,
// reject, request changes (FR11). The applicant side is in application.routes.js.
const express = require('express');
const User = require('../../models/User');
const { requireAuth, requireRole } = require('../../middleware/auth');
const { body, z } = require('../../middleware/validate');
const { notify, audit } = require('../../services/notify');
const storage = require('../../services/storage');
const { notFound, conflict } = require('../../utils/errors');
const { ROLE_LABEL, userRow, loadUser } = require('../user/user.helpers');

const router = express.Router();
router.use(requireAuth, requireRole('admin'));

// ---------- Verification (FR11) ----------
router.get('/verifications', async (req, res) => {
  const role = req.query.role === 'doctor' ? 'doctor' : req.query.role === 'counsellor' ? 'counsellor' : { $in: ['counsellor', 'doctor'] };
  const status = String(req.query.status || 'pending');
  const vs = status === 'all' ? { $in: ['pending', 'changes_requested', 'approved', 'rejected'] } : status;
  const list = await User.find({ role, 'verification.status': vs }).sort({ 'verification.submittedAt': -1 });
  res.json({ applications: list.map((u) => ({ ...userRow(u), title: u.professional?.title, submittedAt: u.verification?.submittedAt })) });
});

router.get('/verifications/:id', async (req, res) => {
  const u = await loadUser(req.params.id);
  if (!u.isStaff) throw notFound('Application not found.');
  res.json({ application: { ...userRow(u), title: u.professional?.title, professional: u.professional, verification: u.toPublic().verification } });
});

router.patch('/verifications/:id/documents/:docId', body(z.object({ checked: z.boolean() })), async (req, res) => {
  const u = await loadUser(req.params.id);
  const d = u.verification?.documents?.id(req.params.docId);
  if (!d) throw notFound('Document not found.');
  d.checked = req.body.checked;
  await u.save();
  res.json({ application: { ...userRow(u), verification: u.toPublic().verification } });
});

// Streams an uploaded credential to the admin (or the owner).
async function sendDocument(req, res, userId, docId) {
  const u = await loadUser(userId);
  const d = u.verification?.documents?.id(docId);
  if (!d) throw notFound('Document not found.');
  if (!(await storage.fileExists(d.storedName))) throw notFound('The file is missing from storage.');
  await audit(req.user, 'access', 'Credential document opened', `${u.name}: ${d.label}`);
  res.setHeader('Content-Type', d.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(d.fileName)}"`);
  storage.openFile(d.storedName).on('error', () => res.end()).pipe(res);
}

router.get('/files/:userId/:docId', (req, res) => sendDocument(req, res, req.params.userId, req.params.docId));

async function decide(req, u, status, historyLabel) {
  if (!u.isStaff) throw notFound('Application not found.');
  if (!['pending', 'changes_requested'].includes(u.verification.status)) throw conflict('Couldn’t save your decision. This application was already decided.', 'STATE_CHANGED');
  u.verification.status = status;
  u.verification.reviewedAt = new Date();
  u.verification.reviewedBy = req.user._id;
  u.verification.history.push({ label: historyLabel, at: new Date() });
}

router.post('/verifications/:id/approve', async (req, res) => {
  const u = await loadUser(req.params.id);
  await decide(req, u, 'approved', 'Approved by Student Affairs');
  u.verification.note = '';
  u.verification.documents.forEach((d) => { d.checked = true; });
  await u.save();
  await notify(u, { type: 'verification', title: 'You’re verified', body: u.role === 'counsellor' ? 'Students can now find and book you. Set your working hours.' : 'You can now receive counsellor referrals.', icon: 'verified', tone: 'green' });
  await audit(req.user, 'verification', `${ROLE_LABEL[u.role]} approved`, u.name);
  res.json({ application: userRow(u) });
});

router.post('/verifications/:id/reject', body(z.object({ reason: z.string().trim().min(1, 'Choose a reason').max(120), message: z.string().trim().max(1000).optional().default('') })), async (req, res) => {
  const u = await loadUser(req.params.id);
  await decide(req, u, 'rejected', 'Not approved');
  u.verification.reason = req.body.reason;
  u.verification.note = req.body.message || req.body.reason;
  await u.save();
  await notify(u, { type: 'verification', title: 'Verification not approved', body: u.verification.note, icon: 'gpp_bad', tone: 'red' });
  await audit(req.user, 'verification', `${ROLE_LABEL[u.role]} rejected`, `${u.name} — ${req.body.reason}`);
  res.json({ application: userRow(u) });
});

router.post('/verifications/:id/request-changes', body(z.object({ items: z.array(z.string().max(60)).min(1, 'Choose what needs updating').max(6), message: z.string().trim().min(1, 'Add a message').max(1000) })), async (req, res) => {
  const u = await loadUser(req.params.id);
  await decide(req, u, 'changes_requested', 'Changes requested');
  u.verification.requestedItems = req.body.items;
  u.verification.note = req.body.message;
  await u.save();
  await notify(u, { type: 'verification', title: 'Please update your application', body: req.body.message, icon: 'feedback', tone: 'amber' });
  await audit(req.user, 'verification', 'Changes requested', `${u.name}: ${req.body.items.join(', ')}`);
  res.json({ application: userRow(u) });
});

module.exports = router;
module.exports.sendDocument = sendDocument;
