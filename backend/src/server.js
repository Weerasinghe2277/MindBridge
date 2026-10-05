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
    if (!env.anthropicKey) console.log('[api] ANTHROPIC_API_KEY not set — Bridge uses built-in supportive replies');
    if (env.isProd && env.demoMode) console.warn('[api] DEMO_MODE is on: one-time codes are returned to the app. Turn it off before real students use MindBridge.');
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
