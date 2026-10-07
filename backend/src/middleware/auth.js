const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const User = require('../models/User');
const { AuthSession } = require('../models');
const { unauthorized, forbidden } = require('../utils/errors');
const { getSettings } = require('../services/settings');

async function issueToken(user, device = 'Unknown device') {
  const jti = crypto.randomUUID();
  const token = jwt.sign({ sub: user._id.toString(), role: user.role, jti }, env.jwtSecret, { expiresIn: env.jwtExpiresIn });
  const { exp } = jwt.decode(token);
  await AuthSession.create({ user: user._id, jti, device: String(device).slice(0, 80), expiresAt: new Date(exp * 1000) });
  return token;
}

// Verifies the bearer token, the server-side session and inactivity timeout (NFR4).
// Safe to run more than once per request: feature modules that share a URL prefix
// (e.g. /api/appointments) each guard their own router.
async function requireAuth(req, _res, next) {
  if (req.user) return next();
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw unauthorized();
  let payload;
  try {
    payload = jwt.verify(token, env.jwtSecret);
  } catch {
    throw unauthorized('Your session has ended. Please sign in again.', 'SESSION_EXPIRED');
  }
  const session = await AuthSession.findOne({ jti: payload.jti });
  if (!session || session.revoked) throw unauthorized('Your session has ended. Please sign in again.', 'SESSION_EXPIRED');
  const { security } = await getSettings();
  const idleMs = security.autoSignOutMinutes * 60 * 1000;
  if (Date.now() - session.lastSeenAt.getTime() > idleMs) {
    session.revoked = true;
    await session.save();
    throw unauthorized(`For your privacy, MindBridge signs you out after ${security.autoSignOutMinutes} minutes of inactivity.`, 'SESSION_EXPIRED');
  }
  const user = await User.findById(payload.sub);
  if (!user) throw unauthorized();
  if (user.status !== 'active') throw unauthorized('This account has been deactivated. Contact Student Affairs.', 'ACCOUNT_DEACTIVATED');
  // Background polling (e.g. unread badge) must not keep an idle session alive.
  if (req.headers['x-background'] !== '1') {
    const now = new Date();
    await AuthSession.updateOne({ _id: session._id }, { lastSeenAt: now });
    await User.updateOne({ _id: user._id }, { lastActiveAt: now });
  }
  req.user = user;
  req.session = session;
  next();
}

const requireRole = (...roles) => (req, _res, next) => {
  if (!roles.includes(req.user.role)) throw forbidden();
  next();
};

// Staff may sign in while verification is pending, but can only use their
// working features once Student Affairs approves them (FR11).
function requireVerified(req, _res, next) {
  if (req.user.isStaff && req.user.verification?.status !== 'approved') {
    throw forbidden('Your account is waiting for verification by Student Affairs.', 'NOT_VERIFIED');
  }
  next();
}

module.exports = { issueToken, requireAuth, requireRole, requireVerified };
