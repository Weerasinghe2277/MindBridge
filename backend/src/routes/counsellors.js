// Student-facing counsellor directory with real-time availability (FR2).
const express = require('express');
const User = require('../models/User');
const Appointment = require('../models/Appointment');
const { requireAuth, requireRole } = require('../middleware/auth');
const { isValidId } = require('../middleware/validate');
const { nextAvailable, slotsForDate, monthOverview } = require('../services/slots');
const T = require('../utils/time');
const { notFound, badRequest } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('student', 'counsellor', 'admin'));

const BASE = { role: 'counsellor', status: 'active', 'verification.status': 'approved' };
const list = (v) => (v ? String(v).split(',').map((s) => s.trim()).filter(Boolean) : []);

function card(u, next, extra = {}) {
  const p = u.professional || {};
  return {
    id: u.id, name: u.name, initials: u.initials, title: p.title, focusAreas: p.focusAreas || [],
    languages: p.languages || [], modes: p.modes || [], gender: u.gender || '', experienceYears: p.experienceYears,
    next: next ? { date: next.date, start: next.start, time: next.time } : null,
    freeToday: next?.freeToday || 0,
    ...extra,
  };
}

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  const modes = list(req.query.mode);
  const focus = list(req.query.focus).map((s) => s.toLowerCase());
  const langs = list(req.query.language).map((s) => s.toLowerCase());
  const gender = String(req.query.gender || '');
  const when = String(req.query.available || 'any');

  const all = await User.find(BASE);
  const today = T.todayStr();
  const weekEnd = T.addDays(today, 7); // "this week" = the next 7 days
  const out = [];
  for (const u of all) {
    const p = u.professional || {};
    const hay = [u.name, p.title, ...(p.focusAreas || [])].join(' ').toLowerCase();
    if (q && !hay.includes(q)) continue;
    if (modes.length && !modes.some((m) => (p.modes || []).includes(m))) continue;
    if (focus.length && !focus.some((f) => (p.focusAreas || []).map((x) => x.toLowerCase()).some((x) => x.includes(f) || f.includes(x)))) continue;
    if (langs.length && !langs.some((l) => (p.languages || []).map((x) => x.toLowerCase()).includes(l))) continue;
    if (gender && ['female', 'male'].includes(gender) && u.gender !== gender) continue;
    const next = await nextAvailable(u);
    if (when === 'today' && (!next || next.date !== today)) continue;
    if (when === 'week' && (!next || next.date >= weekEnd)) continue;
    out.push(card(u, next));
  }
  // Sorted by next available slot, as in the design.
  out.sort((a, b) => (a.next?.start || '9999').localeCompare(b.next?.start || '9999'));
  res.json({ counsellors: out, favorites: (req.user.favoriteCounsellors || []).map(String) });
});

async function load(id) {
  if (!isValidId(id)) throw notFound('Counsellor not found.');
  const u = await User.findOne({ _id: id, ...BASE });
  if (!u) throw notFound('Counsellor not found.');
  return u;
}

router.get('/:id', async (req, res) => {
  const u = await load(req.params.id);
  const next = await nextAvailable(u);
  const nextSlots = [];
  for (let i = 0; i < 21 && nextSlots.length < 3; i++) {
    const slots = await slotsForDate(u, T.addDays(T.todayStr(), i));
    for (const s of slots) if (s.available && nextSlots.length < 3) nextSlots.push(s);
  }
  const p = u.professional || {};
  res.json({
    counsellor: card(u, next, {
      about: p.about || '', qualifications: p.qualifications || '', room: p.room || '',
      sessionLength: u.availability?.sessionLength || 30,
      sessionsCompleted: await Appointment.countDocuments({ counsellor: u._id, status: 'completed' }),
      verified: true,
      favorite: (req.user.favoriteCounsellors || []).some((f) => f.equals(u._id)),
    }),
    nextSlots,
  });
});

router.get('/:id/month', async (req, res) => {
  const u = await load(req.params.id);
  const month = String(req.query.month || T.todayStr().slice(0, 7));
  if (!/^\d{4}-\d{2}$/.test(month)) throw badRequest('Invalid month');
  res.json({ month, days: await monthOverview(u, month, { excludeId: isValidId(req.query.exclude) ? req.query.exclude : undefined }) });
});

router.get('/:id/slots', async (req, res) => {
  const u = await load(req.params.id);
  const date = String(req.query.date || '');
  if (!T.isDateStr(date)) throw badRequest('Choose a valid date');
  const slots = await slotsForDate(u, date, { excludeId: isValidId(req.query.exclude) ? req.query.exclude : undefined });
  let nextOpening = null;
  if (!slots.some((s) => s.available)) {
    for (let i = 1; i <= 21 && !nextOpening; i++) {
      const d = T.addDays(date, i);
      const s = (await slotsForDate(u, d)).find((x) => x.available);
      if (s) nextOpening = { date: d, ...s };
    }
  }
  res.json({ date, slots, nextOpening });
});

router.post('/:id/favorite', requireRole('student'), async (req, res) => {
  const u = await load(req.params.id);
  const has = req.user.favoriteCounsellors.some((f) => f.equals(u._id));
  await User.updateOne({ _id: req.user._id }, has ? { $pull: { favoriteCounsellors: u._id } } : { $addToSet: { favoriteCounsellors: u._id } });
  res.json({ favorite: !has });
});

module.exports = router;
