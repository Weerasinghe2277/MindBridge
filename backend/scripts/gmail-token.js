// One-time setup: gets the GMAIL_REFRESH_TOKEN that lets the API send one-time codes from
// mindbrige.support@gmail.com through the Gmail API.
//   1. Put GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET in backend/.env (Google Cloud "Desktop app" OAuth client).
//   2. npm run gmail-token
//   3. Open the printed link, sign in as mindbrige.support@gmail.com and allow "Send email".
//   4. Copy the printed GMAIL_REFRESH_TOKEN into backend/.env and into Render's environment.
const http = require('http');
const env = require('../src/config/env');

const { clientId, clientSecret } = env.mail.gmail;
if (!clientId || !clientSecret) {
  console.error('Set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET in backend/.env first.');
  process.exit(1);
}

const PORT = 53682;
const redirectUri = `http://127.0.0.1:${PORT}`;
const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
  client_id: clientId,
  redirect_uri: redirectUri,
  response_type: 'code',
  scope: 'https://www.googleapis.com/auth/gmail.send',
  access_type: 'offline',
  prompt: 'consent',
  login_hint: 'mindbrige.support@gmail.com',
});

const server = http.createServer(async (req, res) => {
  const code = new URL(req.url, redirectUri).searchParams.get('code');
  if (!code) {
    res.end('No code in the request.');
    return;
  }
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, grant_type: 'authorization_code' }),
  });
  const data = await r.json();
  if (!data.refresh_token) {
    res.end('Google did not return a refresh token. Check the terminal.');
    console.error('Token request failed:', data);
  } else {
    res.end('Done. You can close this tab and go back to the terminal.');
    console.log(`\nGMAIL_REFRESH_TOKEN=${data.refresh_token}\n`);
  }
  server.close();
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('Open this link and sign in as mindbrige.support@gmail.com:\n');
  console.log(authUrl);
});
