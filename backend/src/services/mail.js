// Emails one-time codes from the MindBridge support Gmail account.
//  1. Gmail API over HTTPS (GMAIL_CLIENT_ID / GMAIL_CLIENT_SECRET / GMAIL_REFRESH_TOKEN). Works on hosts
//     that block SMTP ports, such as Render's free plan.
//  2. SMTP (SMTP_HOST ...): Brevo's relay on port 2525 (works on Render), or Gmail with an app password locally.
//  3. Neither: development only — the code is logged and the API returns it as `devOtp`.
const nodemailer = require('nodemailer');
const env = require('../config/env');
const { ApiError } = require('../utils/errors');

const { gmail, smtp } = env.mail;

let smtpTransport = null;
if (!gmail.enabled && smtp.host) {
  smtpTransport = nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.port === 465,
    // Other ports (587, or 2525 for Brevo on Render) must upgrade with STARTTLS before logging in.
    requireTLS: smtp.port !== 465,
    auth: smtp.user ? { user: smtp.user, pass: smtp.pass } : undefined,
    // Fail fast instead of keeping the student waiting if the mail server can't be reached.
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });
}

// Builds the raw MIME message for the Gmail API.
const composer = nodemailer.createTransport({ streamTransport: true, buffer: true, newline: 'unix' });

let accessToken = null;
let accessTokenExpires = 0;

async function gmailAccessToken() {
  if (accessToken && Date.now() < accessTokenExpires - 60000) return accessToken;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: gmail.clientId,
      client_secret: gmail.clientSecret,
      refresh_token: gmail.refreshToken,
      grant_type: 'refresh_token',
    }),
    signal: AbortSignal.timeout(10000),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`token refresh failed: ${data.error_description || data.error || res.status}`);
  accessToken = data.access_token;
  accessTokenExpires = Date.now() + (data.expires_in || 3600) * 1000;
  return accessToken;
}

async function sendViaGmailApi(message) {
  const { message: raw } = await composer.sendMail(message);
  const res = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: { Authorization: `Bearer ${await gmailAccessToken()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ raw: raw.toString('base64url') }),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    if (res.status === 401) accessToken = null;
    throw new Error(`Gmail API ${res.status}: ${data.error?.message || 'send failed'}`);
  }
}

const CONTENT = {
  verify_email: {
    subject: 'Verify your MindBridge account',
    heading: 'Verify your email',
    intro: 'Welcome to MindBridge! Enter this code in the app to verify your email address.',
  },
  login_2fa: {
    subject: 'Your MindBridge sign-in code',
    heading: 'Your sign-in code',
    intro: 'Enter this code in the app to finish signing in to MindBridge.',
  },
  reset_password: {
    subject: 'Reset your MindBridge password',
    heading: 'Reset your password',
    intro: 'We received a request to reset your MindBridge password. Enter this code in the app to choose a new one.',
  },
};

function buildEmail(purpose, code) {
  const c = CONTENT[purpose];
  const text = `${c.heading}\n\n${c.intro}\n\nYour code: ${code}\n\nThis code expires in 10 minutes. If you didn't request it, you can safely ignore this email.\n\n— MindBridge Support`;
  const html = `<!doctype html>
<html><body style="margin:0;padding:24px 12px;background:#f4f6fb;font-family:Arial,Helvetica,sans-serif;color:#1f2937">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#ffffff;border-radius:16px;padding:32px 28px">
      <tr><td style="font-size:20px;font-weight:bold;color:#4f46e5">MindBridge</td></tr>
      <tr><td style="padding-top:20px;font-size:18px;font-weight:bold">${c.heading}</td></tr>
      <tr><td style="padding-top:8px;font-size:15px;line-height:22px;color:#4b5563">${c.intro}</td></tr>
      <tr><td align="center" style="padding:24px 0">
        <div style="display:inline-block;padding:14px 24px;background:#eef2ff;border-radius:12px;font-size:32px;font-weight:bold;letter-spacing:8px;color:#312e81">${code}</div>
      </td></tr>
      <tr><td style="font-size:13px;line-height:20px;color:#6b7280">This code expires in 10 minutes. If you didn't request it, you can safely ignore this email.</td></tr>
      <tr><td style="padding-top:24px;font-size:13px;color:#9ca3af">— MindBridge Support</td></tr>
    </table>
  </td></tr></table>
</body></html>`;
  return { subject: `${c.subject}: ${code}`, text, html };
}

async function sendCode(email, purpose, code) {
  if (!env.mail.enabled) {
    console.log(`[mail:dev] ${purpose} code for ${email}: ${code}`);
    return;
  }
  const message = { from: env.mail.from, to: email, ...buildEmail(purpose, code) };
  try {
    if (gmail.enabled) await sendViaGmailApi(message);
    else await smtpTransport.sendMail(message);
  } catch (err) {
    console.error(`[mail] could not send ${purpose} code to ${email}: ${err.message}`);
    throw new ApiError(503, 'EMAIL_FAILED', 'We couldn’t send the email right now. Please try again in a minute.');
  }
}

module.exports = { sendCode };
