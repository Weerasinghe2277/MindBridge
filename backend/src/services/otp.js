const { Otp } = require('../models');
const { randomCode, sha256 } = require('../utils/crypto');
const { sendCode } = require('./mail');
const env = require('../config/env');
const { badRequest } = require('../utils/errors');

const TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;

async function createOtp(email, purpose) {
  const code = randomCode(6);
  await Otp.deleteMany({ email, purpose });
  await Otp.create({ email, purpose, codeHash: sha256(`${purpose}:${code}`), expiresAt: new Date(Date.now() + TTL_MS) });
  await sendCode(email, purpose, code);
  return env.exposeDevOtp ? { devOtp: code } : {};
}

async function consumeOtp(email, purpose, code) {
  const otp = await Otp.findOne({ email, purpose });
  if (!otp || otp.expiresAt < new Date()) throw badRequest('That code has expired. Request a new one.', 'OTP_EXPIRED');
  if (otp.attempts >= MAX_ATTEMPTS) {
    await otp.deleteOne();
    throw badRequest('Too many attempts. Request a new code.', 'OTP_LOCKED');
  }
  if (otp.codeHash !== sha256(`${purpose}:${String(code).trim()}`)) {
    otp.attempts += 1;
    await otp.save();
    throw badRequest('That code isn’t right. Check the email and try again.', 'OTP_INVALID');
  }
  await otp.deleteOne();
}

module.exports = { createOtp, consumeOtp };
