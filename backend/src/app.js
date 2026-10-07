const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const mongoose = require('mongoose');
const env = require('./config/env');
const { sanitize } = require('./middleware/validate');
const { ApiError } = require('./utils/errors');

const app = express();
app.set('trust proxy', 1);
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({
  origin: env.corsOrigins.includes('*') ? true : env.corsOrigins,
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Background'],
}));
app.use(express.json({ limit: '200kb' }));
app.use(sanitize);
if (!env.isProd) app.use(morgan('dev'));

app.get('/api/health', (_req, res) => res.json({ ok: true, db: mongoose.connection.readyState === 1, time: new Date() }));

// Public client configuration (no personal data).
app.get('/api/config', async (_req, res) => {
  const { security, privacy } = await require('./services/settings').getSettings();
  res.json({ autoSignOutMinutes: security.autoSignOutMinutes, showHelplineEverywhere: privacy.showHelplineEverywhere, helpline: '1926' });
});

// Shared / platform routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/me', require('./routes/me'));
app.use('/api/counsellors', require('./routes/counsellors'));
app.use('/api/staff', require('./routes/staff'));
app.use('/api/mood/journal', require('./routes/journal'));
app.use('/api/notifications', require('./routes/notifications'));
app.use('/api/wellness', require('./routes/wellness'));
app.use('/api/music', require('./routes/music'));
app.use('/api/doctor', require('./routes/doctor'));
app.use('/api/admin/reports', require('./routes/reports'));
app.use('/api/download', require('./routes/downloads'));

// Feature modules — one folder per CRUD, see src/modules/README.md for who owns what.
// Member 1
app.use('/api/appointments', require('./modules/appointment/appointment.routes'));
app.use('/api/staff', require('./modules/availability/availability.routes'));
// Member 2
app.use('/api/auth', require('./modules/user/signup.routes'));
app.use('/api/admin', require('./modules/user/user.routes'));
app.use('/api/me', require('./modules/counsellor-approval/application.routes'));
app.use('/api/admin', require('./modules/counsellor-approval/approval.routes'));
// Member 3
app.use('/api/mood', require('./modules/mood/mood.routes'));
app.use('/api/appointments', require('./modules/counselling-session/session.routes'));
// Member 4
app.use('/api/articles', require('./modules/article/article.routes'));
app.use('/api/referrals', require('./modules/referral/referral.routes'));

app.use('/api/admin', require('./routes/admin'));

app.use('/api', (_req, _res, next) => next(new ApiError(404, 'NOT_FOUND', 'Endpoint not found.')));

// Single error format for the app: { error: { code, message, details? } }
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message, details: err.details } });
  }
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_JSON', message: 'Malformed request body.' } });
  }
  if (err?.name === 'MulterError') {
    const msg = err.code === 'LIMIT_FILE_SIZE' ? 'Files must be 5 MB or smaller.' : 'Upload failed.';
    return res.status(400).json({ error: { code: 'BAD_FILE', message: msg } });
  }
  if (err?.name === 'ValidationError') {
    const first = Object.values(err.errors)[0];
    return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: first?.message || 'Invalid data.', details: { field: first?.path } } });
  }
  if (err?.name === 'CastError') {
    return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Not found.' } });
  }
  console.error(err);
  return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Something went wrong on our side. Nothing was saved halfway — please try again.' } });
});

module.exports = app;
