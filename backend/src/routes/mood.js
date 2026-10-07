// FR9 — private mood check-ins, insights and journal. Visible only to the student.
const express = require('express');
const { MoodEntry, JournalEntry } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z, isValidId } = require('../middleware/validate');
const T = require('../utils/time');
const { notFound, badRequest } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('student'));

const LABELS = ['Awful', 'Low', 'Okay', 'Good', 'Great'];
const WD = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const avg = (a) => (a.length ? a.reduce((t, x) => t + x, 0) / a.length : null);

const entryOut = (e) => ({ id: e.id, mood: e.mood, label: LABELS[e.mood], factors: e.factors, note: e.note || '', date: e.date, createdAt: e.createdAt, source: e.source });

async function streakFor(student) {
  const dates = new Set((await MoodEntry.find({ student }).select('date').lean()).map((e) => e.date));
  let d = T.todayStr();
  if (!dates.has(d)) d = T.addDays(d, -1);
  let n = 0;
  while (dates.has(d)) { n += 1; d = T.addDays(d, -1); }
  return n;
}

router.post('/', body(z.object({
  mood: z.number().int().min(0).max(4),
  factors: z.array(z.string().trim().max(30)).max(10).optional().default([]),
  note: z.string().trim().max(1000).optional().default(''),
  source: z.enum(['checkin', 'game', 'breathing']).optional().default('checkin'),
})), async (req, res) => {
  const e = await MoodEntry.create({ student: req.user._id, ...req.body, date: T.todayStr() });
  const streak = await streakFor(req.user._id);
  // Gentle, non-clinical suggestion based on what the student reported.
  let suggestion = { kind: 'breathing', title: '2-minute box breathing', sub: 'Good for exam nerves' };
  if (e.factors.includes('Sleep')) suggestion = { kind: 'article', title: 'Sleeping well during exam weeks', sub: 'A 5-minute read from our counsellors' };
  if (e.mood <= 1) suggestion = { kind: 'counsellor', title: 'Talk to a counsellor', sub: 'Free, confidential sessions this week' };
  res.status(201).json({ entry: entryOut(e), streak, suggestion });
});

router.get('/today', async (req, res) => {
  const e = await MoodEntry.findOne({ student: req.user._id, date: T.todayStr() }).sort({ createdAt: -1 });
  res.json({ entry: e ? entryOut(e) : null, streak: await streakFor(req.user._id) });
});

// Latest mood per day for a month — drives the mood calendar.
router.get('/calendar', async (req, res) => {
  const month = String(req.query.month || T.todayStr().slice(0, 7));
  if (!/^\d{4}-\d{2}$/.test(month)) throw badRequest('Invalid month');
  const list = await MoodEntry.find({ student: req.user._id, date: { $gte: `${month}-01`, $lte: `${month}-31` } }).sort({ createdAt: 1 }).lean();
  const days = {};
  for (const e of list) days[e.date] = e.mood;
  res.json({ month, days, streak: await streakFor(req.user._id) });
});

router.get('/history', async (req, res) => {
  const range = req.query.range === 'month' ? 'month' : 'week';
  const today = T.todayStr();
  let bars; let from;
  if (range === 'week') {
    from = T.weekStart(today);
    const list = await MoodEntry.find({ student: req.user._id, date: { $gte: from } }).lean();
    bars = [0, 1, 2, 3, 4, 5, 6].map((i) => {
      const d = T.addDays(from, i);
      const v = avg(list.filter((e) => e.date === d).map((e) => e.mood));
      return { label: 'MTWTFSS'[i], date: d, value: v === null ? null : +(v + 1).toFixed(1) };
    });
  } else {
    from = T.addDays(today, -27);
    const list = await MoodEntry.find({ student: req.user._id, date: { $gte: from } }).lean();
    bars = [0, 1, 2, 3].map((w) => {
      const s = T.addDays(from, w * 7); const e = T.addDays(s, 7);
      const v = avg(list.filter((x) => x.date >= s && x.date < e).map((x) => x.mood));
      return { label: `W${w + 1}`, date: s, value: v === null ? null : +(v + 1).toFixed(1) };
    });
  }
  const entries = await MoodEntry.find({ student: req.user._id, date: { $gte: from } }).sort({ createdAt: -1 }).limit(30);
  const vals = entries.map((e) => e.mood);
  const mostly = vals.length ? LABELS[Math.round(avg(vals))] : null;
  const withVal = bars.filter((b) => b.value !== null);
  const lowest = withVal.length > 1 ? withVal.reduce((m, b) => (b.value < m.value ? b : m)) : null;
  let summary = 'No check-ins yet in this period';
  if (mostly) {
    summary = `Mostly “${mostly}”`;
    if (lowest && range === 'week') summary += ` · lowest on ${WD[T.weekdayOf(lowest.date) - 1]}`;
  }
  res.json({ range, bars, summary, entries: entries.map(entryOut), streak: await streakFor(req.user._id) });
});

router.get('/insights', async (req, res) => {
  const range = ['week', 'month', 'semester'].includes(req.query.range) ? req.query.range : 'week';
  const today = T.todayStr();
  const buckets = range === 'week' ? 6 : range === 'month' ? 4 : 5;
  const len = range === 'week' ? 7 : 30;
  const end = range === 'week' ? T.addDays(T.weekStart(today), 7) : T.addDays(today, 1);
  const start = T.addDays(end, -buckets * len);
  const list = await MoodEntry.find({ student: req.user._id, date: { $gte: start, $lt: end } }).lean();
  const bars = Array.from({ length: buckets }, (_, i) => {
    const s = T.addDays(start, i * len); const e = T.addDays(s, len);
    const v = avg(list.filter((x) => x.date >= s && x.date < e).map((x) => x.mood));
    return { label: range === 'week' ? `W${i + 1}` : `M${i + 1}`, value: v === null ? null : +(v + 1).toFixed(1) };
  });
  const counts = {};
  for (const e of list) for (const f of e.factors || []) if (f !== 'Nothing specific') counts[f] = (counts[f] || 0) + 1;
  const triggers = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([label, value]) => ({ label, value }));

  // Pattern: which factor appears most on low days.
  let pattern = null;
  const low = list.filter((e) => e.mood <= 1);
  if (low.length >= 2) {
    const lc = {};
    for (const e of low) for (const f of e.factors || []) lc[f] = (lc[f] || 0) + 1;
    const top = Object.entries(lc).sort((a, b) => b[1] - a[1])[0];
    if (top) pattern = `Your mood is lowest on days you mention “${top[0]}”. Booking a session early may help.`;
  } else if (list.length >= 5) {
    const trend = bars.filter((b) => b.value !== null);
    if (trend.length >= 2 && trend[trend.length - 1].value > trend[0].value) pattern = 'Your average mood is trending up. Keep doing what’s working.';
  }
  res.json({ range, bars, triggers, pattern, total: list.length });
});

router.delete('/:id', async (req, res) => {
  if (!isValidId(req.params.id)) throw notFound();
  await MoodEntry.deleteOne({ _id: req.params.id, student: req.user._id });
  res.json({ deleted: true });
});

// ---------- Journal ----------
const journalOut = (j, full = true) => ({
  id: j.id, title: j.title || 'Untitled', mood: j.mood, moodLabel: j.mood != null ? LABELS[j.mood] : null, tags: j.tags,
  body: full ? (j.body || '') : undefined, excerpt: (j.body || '').slice(0, 80), createdAt: j.createdAt, updatedAt: j.updatedAt,
});

const journalSchema = z.object({
  title: z.string().trim().min(1, 'Give it a name').max(120),
  body: z.string().trim().min(1, 'Write a few words').max(10000),
  mood: z.number().int().min(0).max(4).nullable().optional(),
  tags: z.array(z.string().trim().max(30)).max(10).optional().default([]),
});

router.get('/journal', async (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  // Entries are encrypted at rest, so search happens after decryption, per student.
  const list = await JournalEntry.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(500);
  const filtered = q ? list.filter((j) => `${j.title} ${j.body} ${(j.tags || []).join(' ')}`.toLowerCase().includes(q)) : list;
  res.json({ entries: filtered.map((j) => journalOut(j, false)), total: list.length });
});

router.post('/journal', body(journalSchema), async (req, res) => {
  const j = await JournalEntry.create({ student: req.user._id, ...req.body });
  res.status(201).json({ entry: journalOut(j) });
});

async function loadJ(req) {
  if (!isValidId(req.params.id)) throw notFound('Entry not found.');
  const j = await JournalEntry.findOne({ _id: req.params.id, student: req.user._id });
  if (!j) throw notFound('Entry not found.');
  return j;
}

router.get('/journal/:id', async (req, res) => res.json({ entry: journalOut(await loadJ(req)) }));

router.put('/journal/:id', body(journalSchema), async (req, res) => {
  const j = await loadJ(req);
  Object.assign(j, req.body);
  await j.save();
  res.json({ entry: journalOut(j) });
});

router.delete('/journal/:id', async (req, res) => {
  const j = await loadJ(req);
  await j.deleteOne();
  res.json({ deleted: true });
});

module.exports = router;
