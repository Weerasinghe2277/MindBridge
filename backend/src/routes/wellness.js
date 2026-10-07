const express = require('express');
const { WellnessEvent, ChatMessage } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z } = require('../middleware/validate');
const bridge = require('../services/bridge');
const T = require('../utils/time');

const router = express.Router();
router.use(requireAuth, requireRole('student'));

router.post('/events', body(z.object({
  kind: z.enum(['breathing', 'game', 'music', 'helpline_tap']),
  detail: z.string().trim().max(60).optional(),
  durationSec: z.number().int().min(0).max(24 * 3600).optional(),
})), async (req, res) => {
  await WellnessEvent.create({ user: req.user._id, ...req.body });
  res.status(201).json({ ok: true });
});

router.get('/stats', async (req, res) => {
  const since = T.fromLocal(T.weekStart(T.todayStr()));
  const ev = await WellnessEvent.find({ user: req.user._id, createdAt: { $gte: since } }).lean();
  const breathing = ev.filter((e) => e.kind === 'breathing');
  res.json({
    breathingSessions: breathing.length,
    breathingMinutes: Math.round(breathing.reduce((t, e) => t + (e.durationSec || 0), 0) / 60),
    gamesPlayed: ev.filter((e) => e.kind === 'game').length,
  });
});

// ---------- Bridge chat (FR10) ----------
router.get('/bridge', async (req, res) => {
  const list = await ChatMessage.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(60);
  res.json({ messages: list.reverse().map((m) => ({ id: m.id, from: m.from, text: m.text, escalated: m.escalated, at: m.createdAt })), ai: bridge.enabled() });
});

router.post('/bridge', body(z.object({ text: z.string().trim().min(1).max(2000) })), async (req, res) => {
  const { text } = req.body;
  const history = (await ChatMessage.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(12)).reverse().map((m) => ({ from: m.from, text: m.text }));
  const crisis = bridge.isCrisis(text);
  await ChatMessage.create({ student: req.user._id, from: 'me', text, escalated: crisis });
  let replyText;
  if (crisis) {
    replyText = bridge.CRISIS_REPLY;
    await WellnessEvent.create({ user: req.user._id, kind: 'bridge_escalation' });
  } else {
    replyText = (await bridge.reply({ firstName: req.user.preferredName || req.user.name.split(' ')[0], history, text })).text;
    await WellnessEvent.create({ user: req.user._id, kind: 'bridge_chat' });
  }
  const ai = await ChatMessage.create({ student: req.user._id, from: 'ai', text: replyText, escalated: crisis });
  res.status(201).json({ reply: { id: ai.id, from: 'ai', text: replyText, at: ai.createdAt }, escalate: crisis });
});

router.delete('/bridge', async (req, res) => {
  await ChatMessage.deleteMany({ student: req.user._id });
  res.json({ cleared: true });
});

module.exports = router;
