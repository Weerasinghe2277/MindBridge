// Relaxing music for the Wellness hub. Students stream tracks; Student Affairs (admin)
// uploads, edits and removes them. Audio is stored in Cloudinary via services/storage.js.
const express = require('express');
const { Track } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z, isValidId } = require('../middleware/validate');
const { uploadOne, AUDIO_TYPES } = require('../middleware/upload');
const { saveMedia, deleteMedia } = require('../services/storage');
const { audit } = require('../services/notify');
const { notFound } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth);

const LOOK = { Sleep: ['bedtime', 'lilac'], Focus: ['graphic_eq', 'amber'], Rain: ['water_drop', 'blue'], Nature: ['forest', 'green'], 'Lo-fi': ['music_note', 'blue'] };

const out = (t) => ({
  id: t.id, title: t.title, artist: t.artist, category: t.category, seconds: t.seconds,
  icon: t.icon, tone: t.tone, url: t.audio?.url || null,
});

router.get('/', async (_req, res) => {
  const list = await Track.find().sort({ createdAt: -1, _id: -1 });
  res.json({ tracks: list.map(out), categories: Track.CATEGORIES });
});

const fields = {
  title: z.string().trim().min(2, 'Add a title').max(80),
  artist: z.string().trim().max(60).optional().default(''),
  category: z.enum(Track.CATEGORIES, { error: 'Choose a category' }),
};

router.post('/', requireRole('admin'), uploadOne({ types: AUDIO_TYPES, maxMb: 20, what: 'an MP3 or M4A file' }), body(z.object(fields)), async (req, res) => {
  const media = await saveMedia(req.file.buffer, { kind: 'audio', folder: 'music' });
  const [icon, tone] = LOOK[req.body.category];
  const t = await Track.create({
    ...req.body, icon, tone, seconds: Math.round(media.durationSec || 0),
    audio: { id: media.id, url: media.url }, addedBy: req.user._id,
  });
  await audit(req.user, 'music', 'Track added', t.title);
  res.status(201).json({ track: out(t) });
});

async function load(id) {
  if (!isValidId(id)) throw notFound('Track not found.');
  const t = await Track.findById(id);
  if (!t) throw notFound('Track not found.');
  return t;
}

router.patch('/:id', requireRole('admin'), body(z.object(fields).partial()), async (req, res) => {
  const t = await load(req.params.id);
  Object.assign(t, req.body);
  if (req.body.category) [t.icon, t.tone] = LOOK[req.body.category];
  await t.save();
  await audit(req.user, 'music', 'Track edited', t.title);
  res.json({ track: out(t) });
});

router.delete('/:id', requireRole('admin'), async (req, res) => {
  const t = await load(req.params.id);
  if (t.audio?.id) await deleteMedia(t.audio.id);
  await t.deleteOne();
  await audit(req.user, 'music', 'Track removed', t.title);
  res.json({ deleted: true });
});

module.exports = router;
