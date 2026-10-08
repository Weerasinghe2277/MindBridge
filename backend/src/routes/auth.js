const crypto = require('crypto');
const express = require('express');
const rateLimit = require('express-rate-limit');
const User = require('../models/User');
const { AuthSession, QuickUnlockKey } = require('../models');
const { body, password, z } = require('../middleware/validate');
const { issueToken, requireAuth } = require('../middleware/auth');
const { createOtp, consumeOtp } = require('../services/otp');
const { getSettings } = require('../services/settings');
const { audit, notify } = require('../services/notify');
const { badRequest, unauthorized } = require('../utils/errors');
const { sha256 } = require('../utils/crypto');

const router = express.Router();
// Sign Up (/register) is in modules/user/signup.routes.js, mounted after this router.

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 50, standardHeaders: 'draft-7', legacyHeaders: false, message: { error: { code: 'RATE_LIMITED', message: 'Too many attempts. Please wait a few minutes and try again.' } } });
router.use(['/login', '/login/2fa', '/register', '/forgot', '/reset', '/verify-email', '/resend', '/quick-unlock/sign-in'], limiter);

const email = z.string().trim().toLowerCase().email('Enter a valid email address');

function sessionPayload(user, token) {
  return { token, user: user.toPublic() };
}

router.post('/verify-email', body(z.object({ email, code: z.string().trim().length(6, 'Enter the 6-digit code'), device: z.string().optional() })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  if (!user) throw badRequest('That code isn’t right.', 'OTP_INVALID');
  await consumeOtp(user.email, 'verify_email', req.body.code);
  user.emailVerified = true;
  await user.save();
  const token = await issueToken(user, req.body.device);
  res.json(sessionPayload(user, token));
});

router.post('/resend', body(z.object({ email, purpose: z.enum(['verify_email', 'reset_password', 'login_2fa']) })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  // Same response whether or not the account exists, so emails can't be enumerated.
  const dev = user ? await createOtp(user.email, req.body.purpose) : {};
  res.json({ sent: true, ...dev });
});

router.post('/login', body(z.object({ email, password: z.string().min(1, 'Enter your password'), device: z.string().optional() })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email }).select('+passwordHash');
  if (!user || !(await user.checkPassword(req.body.password))) {
    throw unauthorized('That email and password don’t match. Check them and try again.', 'INVALID_CREDENTIALS');
  }
  if (user.status !== 'active') throw unauthorized('This account has been deactivated. Contact Student Affairs.', 'ACCOUNT_DEACTIVATED');
  if (!user.emailVerified) {
    const dev = await createOtp(user.email, 'verify_email');
    return res.json({ needsVerification: true, email: user.email, ...dev });
  }
  const { security } = await getSettings();
  if (user.role === 'admin' || (user.isStaff && security.staffTwoFactor)) {
    const dev = await createOtp(user.email, 'login_2fa');
    return res.json({ twoFactor: true, email: user.email, ...dev });
  }
  const token = await issueToken(user, req.body.device);
  res.json(sessionPayload(user, token));
});

router.post('/login/2fa', body(z.object({ email, code: z.string().trim().length(6, 'Enter the 6-digit code'), device: z.string().optional() })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  if (!user) throw badRequest('That code isn’t right.', 'OTP_INVALID');
  await consumeOtp(user.email, 'login_2fa', req.body.code);
  const token = await issueToken(user, req.body.device);
  if (user.role === 'admin') await audit(user, 'auth', 'Admin signed in', req.body.device || 'Unknown device');
  res.json(sessionPayload(user, token));
});

router.post('/forgot', body(z.object({ email })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  const dev = user ? await createOtp(user.email, 'reset_password') : {};
  res.json({ sent: true, email: req.body.email, ...dev });
});

// Checks a reset code without consuming it, so the app can move to the "new password" step.
router.post('/reset/check', body(z.object({ email, code: z.string().trim().length(6) })), async (req, res) => {
  const { Otp } = require('../models');
  const { sha256 } = require('../utils/crypto');
  const otp = await Otp.findOne({ email: req.body.email, purpose: 'reset_password' });
  const ok = otp && otp.expiresAt > new Date() && otp.attempts < 5 && otp.codeHash === sha256(`reset_password:${req.body.code}`);
  if (!ok) {
    if (otp) { otp.attempts += 1; await otp.save(); }
    throw badRequest('That code isn’t right. Check the email and try again.', 'OTP_INVALID');
  }
  res.json({ valid: true });
});

router.post('/reset', body(z.object({ email, code: z.string().trim().length(6), password })), async (req, res) => {
  const user = await User.findOne({ email: req.body.email }).select('+passwordHash');
  if (!user) throw badRequest('That code isn’t right.', 'OTP_INVALID');
  await consumeOtp(user.email, 'reset_password', req.body.code);
  await user.setPassword(req.body.password);
  user.emailVerified = true;
  await user.save();
  await AuthSession.updateMany({ user: user._id }, { revoked: true });
  await revokeQuickUnlock(user);
  res.json({ reset: true });
});

router.post('/logout', requireAuth, async (req, res) => {
  req.session.revoked = true;
  await req.session.save();
  res.json({ signedOut: true });
});

// ---------- Quick unlock (fingerprint, face, pattern or PIN) ----------
// The phone checks the user's fingerprint/face/screen lock itself; the server only sees the
// device key the phone releases afterwards. Keys last 90 days from their last use.
const QUICK_UNLOCK_DAYS = 90;
const newUnlockKey = () => crypto.randomBytes(32).toString('base64url');
const unlockExpiry = () => new Date(Date.now() + QUICK_UNLOCK_DAYS * 24 * 60 * 60 * 1000);
const unlockKey = z.string().min(20).max(200);

async function syncBiometricFlag(userId) {
  const on = (await QuickUnlockKey.countDocuments({ user: userId, expiresAt: { $gt: new Date() } })) > 0;
  await User.updateOne({ _id: userId }, { 'privacy.biometricUnlock': on });
}

// Turns quick unlock on for the phone the user is signed in on.
router.post('/quick-unlock', requireAuth, body(z.object({ device: z.string().optional() })), async (req, res) => {
  const key = newUnlockKey();
  await QuickUnlockKey.create({ user: req.user._id, keyHash: sha256(key), device: String(req.body.device || req.session.device || 'Unknown device').slice(0, 80), expiresAt: unlockExpiry() });
  await syncBiometricFlag(req.user._id);
  const user = await User.findById(req.user._id);
  res.status(201).json({ unlockKey: key, user: user.toPublic() });
});

// Signs in with a device key. The key is replaced on every use, so a copied key stops working.
router.post('/quick-unlock/sign-in', body(z.object({ unlockKey, device: z.string().optional() })), async (req, res) => {
  const record = await QuickUnlockKey.findOne({ keyHash: sha256(req.body.unlockKey), expiresAt: { $gt: new Date() } });
  const user = record && (await User.findById(record.user));
  if (!record || !user) throw unauthorized('Quick unlock has been turned off on this phone. Sign in with your password.', 'QUICK_UNLOCK_INVALID');
  if (user.status !== 'active') throw unauthorized('This account has been deactivated. Contact Student Affairs.', 'ACCOUNT_DEACTIVATED');
  const next = newUnlockKey();
  record.keyHash = sha256(next);
  record.lastUsedAt = new Date();
  record.expiresAt = unlockExpiry();
  await record.save();
  const device = req.body.device || record.device;
  const token = await issueToken(user, device);
  if (user.role === 'admin') await audit(user, 'auth', 'Admin signed in with quick unlock', device || 'Unknown device');
  res.json({ ...sessionPayload(user, token), unlockKey: next });
});

// Turns quick unlock off for one phone. Holding the key is enough, so it also works signed out.
router.post('/quick-unlock/remove', body(z.object({ unlockKey })), async (req, res) => {
  const record = await QuickUnlockKey.findOneAndDelete({ keyHash: sha256(req.body.unlockKey) });
  if (record) await syncBiometricFlag(record.user);
  res.json({ removed: !!record });
});

async function revokeQuickUnlock(user) {
  await QuickUnlockKey.deleteMany({ user: user._id });
  await User.updateOne({ _id: user._id }, { 'privacy.biometricUnlock': false });
}

router.get('/me', requireAuth, async (req, res) => {
  res.json({ user: req.user.toPublic() });
});

module.exports = router;
module.exports.revokeQuickUnlock = revokeQuickUnlock;
