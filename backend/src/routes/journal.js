// Private journal (FR9). Mounted at /api/mood/journal. Visible only to the student.
const express = require('express');
const { JournalEntry } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z, isValidId } = require('../middleware/validate');
const { LABELS } = require('../modules/mood/mood.routes');
const { notFound } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('student'));

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

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  // Entries are encrypted at rest, so search happens after decryption, per student.
  const list = await JournalEntry.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(500);
  const filtered = q ? list.filter((j) => `${j.title} ${j.body} ${(j.tags || []).join(' ')}`.toLowerCase().includes(q)) : list;
  res.json({ entries: filtered.map((j) => journalOut(j, false)), total: list.length });
});

router.post('/', body(journalSchema), async (req, res) => {
  const j = await JournalEntry.create({ student: req.user._id, ...req.body });
  res.status(201).json({ entry: journalOut(j) });
});

async function loadJ(req) {
  if (!isValidId(req.params.id)) throw notFound('Entry not found.');
  const j = await JournalEntry.findOne({ _id: req.params.id, student: req.user._id });
  if (!j) throw notFound('Entry not found.');
  return j;
}

router.get('/:id', async (req, res) => res.json({ entry: journalOut(await loadJ(req)) }));

router.put('/:id', body(journalSchema), async (req, res) => {
  const j = await loadJ(req);
  Object.assign(j, req.body);
  await j.save();
  res.json({ entry: journalOut(j) });
});

router.delete('/:id', async (req, res) => {
  const j = await loadJ(req);
  await j.deleteOne();
  res.json({ deleted: true });
});

module.exports = router;
