const env = require('./config/env');
const { connectDb, disconnectDb, isMemory } = require('./config/db');
const app = require('./app');
const { startScheduler } = require('./services/scheduler');

async function main() {
  await connectDb();
  // The in-memory database starts empty, so fill it with demo data automatically.
  if (isMemory()) await require('./seed/seed').seed({ quiet: true });
  else if (env.seedIfEmpty && (await require('./models/User').estimatedDocumentCount()) === 0) {
    console.log('[api] empty database: loading demo data…');
    await require('./seed/seed').seed();
  }
  const server = app.listen(env.port, '0.0.0.0', () => {
    console.log(`[api] MindBridge API listening on http://localhost:${env.port}/api`);
    if (!env.geminiKey) console.log('[api] GEMINI_API_KEY not set — Bridge uses built-in supportive replies');
    else console.log(`[api] Bridge uses Gemini (${env.bridgeModel})`);
    if (env.mail.gmail.enabled) console.log('[api] One-time codes are emailed with the Gmail API');
    else if (env.mail.enabled) console.log(`[api] One-time codes are emailed over SMTP (${env.mail.smtp.host})`);
    else if (env.exposeDevOtp) console.warn('[api] Email is not configured: one-time codes are returned to the app. Set up email before real students use MindBridge.');
  });
  const timer = startScheduler();
  const shutdown = async () => {
    clearInterval(timer);
    server.close();
    await disconnectDb();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((e) => {
  console.error('[api] failed to start:', e.message);
  process.exit(1);
});
