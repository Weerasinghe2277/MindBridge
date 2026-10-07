// Sends one-time codes. With SMTP configured it emails them; otherwise (development)
// it logs them to the console and the API can return them as `devOtp`.
const nodemailer = require('nodemailer');
const env = require('../config/env');

let transport = null;
if (env.smtp.host) {
  transport = nodemailer.createTransport({
    host: env.smtp.host,
    port: env.smtp.port,
    secure: env.smtp.port === 465,
    auth: env.smtp.user ? { user: env.smtp.user, pass: env.smtp.pass } : undefined,
  });
}

const SUBJECT = {
  verify_email: 'Verify your MindBridge account',
  reset_password: 'Your MindBridge password reset code',
  login_2fa: 'Your MindBridge sign-in code',
};

async function sendCode(email, purpose, code) {
  const text = `Your MindBridge code is ${code}. It expires in 10 minutes. If you didn't request it, you can ignore this email.`;
  if (!transport) {
    console.log(`[mail:dev] ${purpose} code for ${email}: ${code}`);
    return;
  }
  await transport.sendMail({ from: env.smtp.from, to: email, subject: SUBJECT[purpose], text });
}

module.exports = { sendCode };
