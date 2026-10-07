// MEMBER 4 — Article Management (CRUD 1)
// Create, view, update, delete, view details and categorize articles, plus cover images.
// Wellness articles: students read, counsellors write, Student Affairs reviews.
const express = require('express');
const User = require('../../models/User');
const Article = require('./article.model');
const { WellnessEvent } = require('../../models');
const { requireAuth, requireRole, requireVerified } = require('../../middleware/auth');
const { body, z, isValidId } = require('../../middleware/validate');
const { uploadOne, IMAGE_TYPES } = require('../../middleware/upload');
const { notify, audit } = require('../../services/notify');
const { saveMedia, deleteMedia } = require('../../services/storage');
const { notFound, conflict, forbidden } = require('../../utils/errors');

const router = express.Router();
router.use(requireAuth);

const CATEGORIES = ['Stress', 'Sleep', 'Academic', 'Relationships', 'Mindfulness'];
const readMinutes = (text) => Math.max(1, Math.round(String(text || '').split(/\s+/).length / 200));

function out(a, { full = false, viewer } = {}) {
  const o = {
    id: a.id, title: a.title, category: a.category, status: a.status,
    author: a.author?.name ? { id: a.author.id, name: a.author.name, title: a.author.professional?.title } : undefined,
    readMinutes: readMinutes(a.body), reads: a.reads,
    excerpt: a.body.slice(0, 140), publishedAt: a.publishedAt, submittedAt: a.submittedAt, updatedAt: a.updatedAt,
    hasRevision: !!a.revision?.submittedAt,
    coverUrl: a.cover?.url || null,
  };
  if (full) o.body = a.body;
  if (viewer && (viewer.role === 'admin' || a.author?._id?.equals?.(viewer._id) || String(a.author) === String(viewer._id))) {
    o.review = a.review?.at ? { reason: a.review.reason, feedback: a.review.feedback, at: a.review.at } : null;
    o.revision = a.revision?.submittedAt ? { title: a.revision.title, category: a.revision.category, body: a.revision.body, submittedAt: a.revision.submittedAt } : null;
  }
  return o;
}

router.get('/categories', (_req, res) => res.json({ categories: CATEGORIES }));

router.get('/', async (req, res) => {
  const q = { status: 'published' };
  if (req.query.category && CATEGORIES.includes(req.query.category)) q.category = req.query.category;
  let list = await Article.find(q).sort({ publishedAt: -1 }).populate('author', 'name professional');
  const s = String(req.query.q || '').trim().toLowerCase();
  if (s) list = list.filter((a) => `${a.title} ${a.category} ${a.body} ${a.author?.name}`.toLowerCase().includes(s));
  const counts = {};
  for (const c of CATEGORIES) counts[c] = await Article.countDocuments({ status: 'published', category: c });
  res.json({ articles: list.map((a) => out(a)), counts, saved: (req.user.savedArticles || []).map(String) });
});

router.get('/saved', requireRole('student'), async (req, res) => {
  const list = await Article.find({ _id: { $in: req.user.savedArticles }, status: 'published' }).populate('author', 'name professional');
  res.json({ articles: list.map((a) => out(a)) });
});

// Counsellor's own articles — must come before "/:id".
router.get('/mine', requireRole('counsellor'), requireVerified, async (req, res) => {
  const list = await Article.find({ author: req.user._id, status: { $ne: 'removed' } }).sort({ updatedAt: -1 }).populate('author', 'name professional');
  const stats = {
    published: list.filter((a) => a.status === 'published').length,
    in_review: list.filter((a) => a.status === 'in_review' || a.revision?.submittedAt).length,
    draft: list.filter((a) => a.status === 'draft' || a.status === 'rejected').length,
  };
  res.json({ articles: list.map((a) => out(a, { viewer: req.user })), stats });
});

async function loadArticle(id) {
  if (!isValidId(id)) throw notFound('Article not found.');
  const a = await Article.findById(id).populate('author', 'name professional');
  if (!a) throw notFound('Article not found.');
  return a;
}

router.get('/:id', async (req, res) => {
  const a = await loadArticle(req.params.id);
  const mine = a.author._id.equals(req.user._id);
  if (a.status !== 'published' && !mine && req.user.role !== 'admin') throw notFound('Article not found.');
  if (a.status === 'published' && req.user.role === 'student') {
    await Article.updateOne({ _id: a._id }, { $inc: { reads: 1 } });
    await WellnessEvent.create({ user: req.user._id, kind: 'article_read', detail: a.category });
  }
  const related = await Article.find({ status: 'published', category: a.category, _id: { $ne: a._id } }).limit(3).populate('author', 'name professional');
  res.json({
    article: out(a, { full: true, viewer: req.user }),
    saved: (req.user.savedArticles || []).some((x) => x.equals(a._id)),
    related: related.map((r) => out(r)),
  });
});

router.post('/:id/save', requireRole('student'), async (req, res) => {
  const a = await loadArticle(req.params.id);
  const has = (req.user.savedArticles || []).some((x) => x.equals(a._id));
  await User.updateOne({ _id: req.user._id }, has ? { $pull: { savedArticles: a._id } } : { $addToSet: { savedArticles: a._id } });
  res.json({ saved: !has });
});

const articleSchema = z.object({
  title: z.string().trim().min(5, 'Use a clear, practical title').max(120),
  category: z.enum(CATEGORIES),
  body: z.string().trim().min(50, 'Write at least a short paragraph (50+ characters)').max(20000),
});

router.post('/', requireRole('counsellor'), requireVerified, body(articleSchema), async (req, res) => {
  const a = await Article.create({ ...req.body, author: req.user._id, status: 'draft' });
  await a.populate('author', 'name professional');
  res.status(201).json({ article: out(a, { full: true, viewer: req.user }) });
});

router.put('/:id', requireRole('counsellor'), requireVerified, body(articleSchema), async (req, res) => {
  const a = await loadArticle(req.params.id);
  if (!a.author._id.equals(req.user._id)) throw forbidden();
  if (a.status === 'published') {
    // Edits to a live article go back to review; the live text stays visible meanwhile.
    a.revision = { ...req.body, submittedAt: undefined };
  } else if (a.status === 'removed') {
    throw conflict('This article was removed by Student Affairs.');
  } else {
    Object.assign(a, req.body);
    if (a.status === 'rejected' || a.status === 'in_review') a.status = 'draft';
  }
  await a.save();
  res.json({ article: out(a, { full: true, viewer: req.user }) });
});

router.post('/:id/submit', requireRole('counsellor'), requireVerified, async (req, res) => {
  const a = await loadArticle(req.params.id);
  if (!a.author._id.equals(req.user._id)) throw forbidden();
  if (a.status === 'published') {
    if (!a.revision?.body) throw conflict('Make an edit before submitting for review.');
    a.revision.submittedAt = new Date();
    a.markModified('revision');
  } else if (['draft', 'rejected'].includes(a.status)) {
    a.status = 'in_review';
    a.submittedAt = new Date();
  } else {
    throw conflict('This article is already in review.');
  }
  await a.save();
  const admins = await User.find({ role: 'admin', status: 'active' });
  await Promise.all(admins.map((ad) => notify(ad, { type: 'article', title: 'Article submitted for review', body: a.revision?.title || a.title, icon: 'article', tone: 'amber', link: { screen: 'article_review', id: a.id } })));
  res.json({ article: out(a, { full: true, viewer: req.user }) });
});

router.delete('/:id', requireRole('counsellor'), requireVerified, async (req, res) => {
  const a = await loadArticle(req.params.id);
  if (!a.author._id.equals(req.user._id)) throw forbidden();
  if (a.status === 'published') throw conflict('Live articles can only be removed by Student Affairs.');
  if (a.cover?.id) await deleteMedia(a.cover.id);
  await a.deleteOne();
  await audit(req.user, 'articles', 'Draft deleted', a.title);
  res.json({ deleted: true });
});

// ---------- Cover image ----------
// Like text edits, a new cover sends an article in review back to draft. Live articles keep their cover.
async function loadOwnEditable(req) {
  const a = await loadArticle(req.params.id);
  if (!a.author._id.equals(req.user._id)) throw forbidden();
  if (!['draft', 'rejected', 'in_review'].includes(a.status)) throw conflict('The cover can only be changed before the article is published.');
  return a;
}

router.put('/:id/cover', requireRole('counsellor'), requireVerified, uploadOne({ types: IMAGE_TYPES, maxMb: 5, what: 'a JPG, PNG or WebP image' }), async (req, res) => {
  const a = await loadOwnEditable(req);
  const media = await saveMedia(req.file.buffer, { kind: 'image', folder: 'articles' });
  if (a.cover?.id) await deleteMedia(a.cover.id);
  a.cover = { id: media.id, url: media.url };
  if (a.status === 'in_review') a.status = 'draft';
  await a.save();
  res.json({ article: out(a, { full: true, viewer: req.user }) });
});

router.delete('/:id/cover', requireRole('counsellor'), requireVerified, async (req, res) => {
  const a = await loadOwnEditable(req);
  if (a.cover?.id) await deleteMedia(a.cover.id);
  a.cover = undefined;
  if (a.status === 'in_review') a.status = 'draft';
  await a.save();
  res.json({ article: out(a, { full: true, viewer: req.user }) });
});

module.exports = router;
module.exports.out = out;
module.exports.CATEGORIES = CATEGORIES;
