// FR5 — in-app notifications for every role.
const express = require('express');
const { Notification } = require('../models');
const { requireAuth } = require('../middleware/auth');
const { isValidId } = require('../middleware/validate');

const router = express.Router();
router.use(requireAuth);

const out = (n) => ({ id: n.id, type: n.type, title: n.title, body: n.body, icon: n.icon, tone: n.tone, link: n.link?.screen ? n.link : null, read: n.read, createdAt: n.createdAt });

router.get('/', async (req, res) => {
  const list = await Notification.find({ user: req.user._id }).sort({ createdAt: -1 }).limit(100);
  res.json({ notifications: list.map(out), unread: list.filter((n) => !n.read).length });
});

router.get('/unread-count', async (req, res) => {
  res.json({ unread: await Notification.countDocuments({ user: req.user._id, read: false }) });
});

router.post('/read-all', async (req, res) => {
  await Notification.updateMany({ user: req.user._id, read: false }, { read: true });
  res.json({ ok: true });
});

router.post('/:id/read', async (req, res) => {
  if (isValidId(req.params.id)) await Notification.updateOne({ _id: req.params.id, user: req.user._id }, { read: true });
  res.json({ ok: true });
});

router.delete('/', async (req, res) => {
  await Notification.deleteMany({ user: req.user._id });
  res.json({ ok: true });
});

module.exports = router;
