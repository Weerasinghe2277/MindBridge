// Student Affairs administration (FR11, FR12). Admins never see session content,
// notes, check-ins or chats — only accounts, credentials, articles and anonymised totals.
// Users & roles are in modules/user, verification in modules/counsellor-approval.
const express = require('express');
const User = require('../models/User');
const Appointment = require('../models/Appointment');
const { Article, AuditLog } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z, isValidId } = require('../middleware/validate');
const { notify, audit } = require('../services/notify');
const { getSettings, updateSettings } = require('../services/settings');
const articles = require('../modules/article/article.routes');
const T = require('../utils/time');
const { notFound, badRequest, conflict } = require('../utils/errors');
const { ROLE_LABEL } = require('../modules/user/user.helpers');

const router = express.Router();
router.use(requireAuth, requireRole('admin'));

// ---------- Dashboard ----------
router.get('/dashboard', async (req, res) => {
  const monthStart = T.fromLocal(`${T.todayStr().slice(0, 7)}-01`);
  const [pendingC, pendingD, toReview, activeStudents, sessions, recent] = await Promise.all([
    User.countDocuments({ role: 'counsellor', 'verification.status': { $in: ['pending'] } }),
    User.countDocuments({ role: 'doctor', 'verification.status': { $in: ['pending'] } }),
    Article.countDocuments({ $or: [{ status: 'in_review' }, { 'revision.submittedAt': { $exists: true, $ne: null } }] }),
    User.countDocuments({ role: 'student', status: 'active' }),
    Appointment.countDocuments({ start: { $gte: monthStart }, status: { $in: ['confirmed', 'completed'] } }),
    AuditLog.find().sort({ createdAt: -1 }).limit(5),
  ]);
  res.json({
    pendingVerifications: pendingC + pendingD, pendingCounsellors: pendingC, pendingDoctors: pendingD,
    articlesToReview: toReview, activeStudents, sessionsThisMonth: sessions,
    totalUsers: await User.countDocuments(),
    roleCounts: Object.fromEntries(await Promise.all(Object.keys(ROLE_LABEL).map(async (r) => [r, await User.countDocuments({ role: r })]))),
    recent: recent.map(logOut),
  });
});

router.get('/activity', async (req, res) => {
  const d = T.todayStr();
  const ws = T.weekStart(d);
  const todayCount = await Appointment.countDocuments({ createdAt: { $gte: T.fromLocal(d), $lt: T.fromLocal(T.addDays(d, 1)) } });
  const since = T.fromLocal(T.addDays(d, -30));
  const recent = await Appointment.find({ createdAt: { $gte: since } }).select('history createdAt flaggedDuplicate').lean();
  const confirmed = recent.filter((a) => a.history.some((h) => h.status === 'confirmed'));
  const fast = confirmed.filter((a) => (a.history.find((h) => h.status === 'confirmed').at - a.createdAt) <= 24 * 3600 * 1000);
  const bars = [];
  for (let i = 0; i < 7; i++) {
    const day = T.addDays(ws, i);
    bars.push({ label: 'MTWTFSS'[i], value: await Appointment.countDocuments({ createdAt: { $gte: T.fromLocal(day), $lt: T.fromLocal(T.addDays(day, 1)) } }) });
  }
  res.json({
    bookingsToday: todayCount,
    confirmedIn24hPct: confirmed.length ? Math.round((fast.length / confirmed.length) * 100) : null,
    duplicatesFlagged: recent.filter((a) => a.flaggedDuplicate).length,
    week: bars,
  });
});

// ---------- Article moderation ----------
router.get('/articles', async (req, res) => {
  const status = String(req.query.status || 'waiting');
  let q;
  if (status === 'waiting') q = { $or: [{ status: 'in_review' }, { status: 'published', 'revision.submittedAt': { $ne: null } }] };
  else if (status === 'published') q = { status: 'published' };
  else if (status === 'rejected') q = { status: { $in: ['rejected', 'removed'] } };
  else throw badRequest('Unknown status');
  const list = await Article.find(q).sort({ updatedAt: -1 }).populate('author', 'name professional');
  const waiting = await Article.countDocuments({ $or: [{ status: 'in_review' }, { status: 'published', 'revision.submittedAt': { $ne: null } }] });
  res.json({ articles: list.map((a) => articles.out(a, { viewer: req.user })), waiting });
});

async function loadArticle(id) {
  if (!isValidId(id)) throw notFound('Article not found.');
  const a = await Article.findById(id).populate('author', 'name professional notificationPrefs');
  if (!a) throw notFound('Article not found.');
  return a;
}

router.get('/articles/:id', async (req, res) => {
  const a = await loadArticle(req.params.id);
  const o = articles.out(a, { full: true, viewer: req.user });
  // When a live article has a pending edit, the reviewer reads the edit.
  if (a.revision?.submittedAt) Object.assign(o, { title: a.revision.title, category: a.revision.category, body: a.revision.body, isRevision: true });
  res.json({ article: o });
});

router.post('/articles/:id/approve', async (req, res) => {
  const a = await loadArticle(req.params.id);
  if (a.status === 'published' && a.revision?.submittedAt) {
    Object.assign(a, { title: a.revision.title, category: a.revision.category, body: a.revision.body });
    a.revision = undefined;
  } else if (a.status === 'in_review') {
    a.status = 'published';
    a.publishedAt = new Date();
  } else throw conflict('Nothing to approve for this article.', 'STATE_CHANGED');
  a.review = { by: req.user._id, at: new Date() };
  await a.save();
  await notify(a.author, { type: 'article', title: 'Article published', body: `“${a.title}” is now live in the Wellness hub.`, icon: 'publish', tone: 'green', link: { screen: 'my_article', id: a.id } });
  await audit(req.user, 'articles', 'Article approved', a.title);
  res.json({ approved: true });
});

router.post('/articles/:id/reject', body(z.object({ reason: z.string().trim().min(1, 'Choose a reason').max(120), feedback: z.string().trim().max(1500).optional().default('') })), async (req, res) => {
  const a = await loadArticle(req.params.id);
  if (a.status === 'published' && a.revision?.submittedAt) {
    a.revision.submittedAt = undefined; // edit returns to the author; live text unchanged
    a.markModified('revision');
  } else if (a.status === 'in_review') a.status = 'rejected';
  else throw conflict('This article isn’t waiting for review.', 'STATE_CHANGED');
  a.review = { reason: req.body.reason, feedback: req.body.feedback, by: req.user._id, at: new Date() };
  await a.save();
  await notify(a.author, { type: 'article', title: 'Article sent back', body: `${req.body.reason}${req.body.feedback ? ` — ${req.body.feedback}` : ''}`, icon: 'article', tone: 'amber', link: { screen: 'my_article', id: a.id } });
  await audit(req.user, 'articles', 'Article sent back', a.title);
  res.json({ rejected: true });
});

router.post('/articles/:id/remove', body(z.object({ reason: z.string().trim().min(1, 'Add a reason').max(300) })), async (req, res) => {
  const a = await loadArticle(req.params.id);
  a.status = 'removed';
  a.review = { reason: req.body.reason, by: req.user._id, at: new Date() };
  await a.save();
  await notify(a.author, { type: 'article', title: 'Article removed', body: `“${a.title}”: ${req.body.reason}`, icon: 'delete', tone: 'red' });
  await audit(req.user, 'articles', 'Article removed', a.title);
  res.json({ removed: true });
});

// ---------- Settings ----------
router.get('/settings', async (req, res) => res.json({ settings: await getSettings() }));

router.patch('/settings/:section', async (req, res) => {
  const section = req.params.section;
  if (!['appointments', 'notifications', 'privacy', 'security'].includes(section)) throw notFound('Unknown settings section.');
  const { next, changed } = await updateSettings(section, req.body || {});
  if (changed.length) await audit(req.user, 'settings', 'Setting changed', `${section}: ${changed.map((k) => `${k} → ${next[section][k]}`).join(', ')}`);
  res.json({ settings: next });
});

// ---------- Activity log ----------
function logOut(l) {
  return { id: l.id, category: l.category, action: l.action, target: l.target, detail: l.detail, actor: l.actorName, at: l.createdAt };
}

router.get('/logs', async (req, res) => {
  const q = {};
  const cat = String(req.query.category || '');
  if (['users', 'verification', 'articles', 'music', 'settings', 'access', 'auth'].includes(cat)) q.category = cat;
  const list = await AuditLog.find(q).sort({ createdAt: -1 }).limit(200);
  res.json({ logs: list.map(logOut) });
});

module.exports = router;
