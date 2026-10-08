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
    // Fail fast instead of keeping the student waiting if the mail server can't be reached.
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
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
  try {
    await transport.sendMail({ from: env.smtp.from, to: email, subject: SUBJECT[purpose], text });
  } catch (err) {
    // Don't break sign-in if email is down (or blocked by the host). With DEMO_MODE the code still
    // shows in the app, and the user can tap "Resend" once email is back.
    console.error(`[mail] could not send ${purpose} code to ${email}: ${err.message}`);
  }
}

module.exports = { sendCode };
