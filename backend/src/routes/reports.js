// FR12 — anonymised usage reports. Every grouped figure smaller than the policy
// minimum (10) is suppressed so no individual student can be identified (NFR1).
const express = require('express');
const PDFDocument = require('pdfkit');
const User = require('../models/User');
const Appointment = require('../models/Appointment');
const { MoodEntry, WellnessEvent, AuditLog } = require('../models');
const { requireAuth, requireRole } = require('../middleware/auth');
const { getSettings } = require('../services/settings');
const T = require('../utils/time');
const { badRequest } = require('../utils/errors');

const router = express.Router();
router.use(requireAuth, requireRole('admin'));

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

async function rangeOf(req) {
  const today = T.todayStr();
  const preset = String(req.query.range || 'month');
  let from; let to;
  if (req.query.from && req.query.to) {
    if (!T.isDateStr(req.query.from) || !T.isDateStr(req.query.to) || req.query.from > req.query.to) throw badRequest('Choose a valid date range');
    from = req.query.from; to = req.query.to;
  } else if (preset === 'last_month') {
    const first = `${today.slice(0, 7)}-01`;
    to = T.addDays(first, -1); from = `${to.slice(0, 7)}-01`;
  } else if (preset === 'semester') {
    from = T.addDays(today, -120); to = today;
  } else {
    from = `${today.slice(0, 7)}-01`; to = today;
  }
  const { privacy } = await getSettings();
  const [y, m] = from.split('-').map(Number);
  return { from, to, start: T.fromLocal(from), end: T.fromLocal(T.addDays(to, 1)), k: privacy.minReportGroupSize, label: preset === 'month' && !req.query.from ? `${['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1]} ${y}` : `${from} – ${to}` };
}

// Suppress small groups: returns null when the group is too small to be anonymous.
const k = (n, min) => (n >= min ? n : null);
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);

async function overview(r) {
  const created = { createdAt: { $gte: r.start, $lt: r.end } };
  const requests = await Appointment.countDocuments(created);
  const supported = (await Appointment.distinct('student', { start: { $gte: r.start, $lt: r.end }, status: { $in: ['confirmed', 'completed'] } })).length;
  const held = await Appointment.find({ start: { $gte: r.start, $lt: r.end }, status: { $in: ['confirmed', 'completed'] } }).select('mode').lean();
  const online = held.filter((a) => a.mode === 'online').length;
  const checkins = await MoodEntry.countDocuments({ date: { $gte: r.from, $lte: r.to } });
  return {
    bookingRequests: k(requests, r.k), studentsSupported: k(supported, r.k),
    onlinePct: held.length >= r.k ? pct(online, held.length) : null, moodCheckins: k(checkins, r.k),
    enoughData: requests >= r.k || checkins >= r.k,
  };
}

async function appointments(r) {
  const list = await Appointment.find({ createdAt: { $gte: r.start, $lt: r.end } }).select('history createdAt status flaggedDuplicate').lean();
  const confirmTimes = list.map((a) => a.history.find((h) => h.status === 'confirmed')).map((h, i) => (h ? (h.at - list[i].createdAt) / 3600000 : null)).filter((x) => x !== null);
  const weeks = [];
  for (let w = 0; ; w++) {
    const s = T.addDays(r.from, w * 7);
    if (s > r.to) break;
    const e = T.addDays(s, 7);
    weeks.push({ label: `W${w + 1}`, value: list.filter((a) => a.createdAt >= T.fromLocal(s) && a.createdAt < T.fromLocal(e)).length });
    if (w > 20) break;
  }
  const count = (fn) => list.filter(fn).length;
  const outcomes = [
    { label: 'Completed', value: count((a) => a.status === 'completed') },
    { label: 'Rescheduled', value: count((a) => a.history.some((h) => h.label === 'Rescheduled')) },
    { label: 'Cancelled', value: count((a) => a.status === 'cancelled') },
    { label: 'Declined', value: count((a) => a.status === 'declined') },
    { label: 'No-show', value: count((a) => a.status === 'no_show') },
  ].map((o) => ({ ...o, value: k(o.value, r.k) }));
  return {
    requests: k(list.length, r.k),
    avgHoursToConfirm: confirmTimes.length >= r.k ? +(confirmTimes.reduce((t, x) => t + x, 0) / confirmTimes.length).toFixed(1) : null,
    completed: k(count((a) => a.status === 'completed'), r.k),
    duplicatePct: list.length >= r.k ? pct(count((a) => a.flaggedDuplicate), list.length) : null,
    weeks: weeks.map((w) => ({ ...w, value: k(w.value, r.k) })),
    outcomes,
  };
}

async function types(r) {
  const held = await Appointment.find({ start: { $gte: r.start, $lt: r.end }, status: { $in: ['confirmed', 'completed'] } }).select('mode').lean();
  const online = held.filter((a) => a.mode === 'online').length;
  const months = [];
  const now = T.todayStr();
  for (let i = 4; i >= 0; i--) {
    const [y, m] = now.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1 - i, 1));
    const ms = dt.toISOString().slice(0, 7);
    const next = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 1)).toISOString().slice(0, 7);
    const l = await Appointment.find({ start: { $gte: T.fromLocal(`${ms}-01`), $lt: T.fromLocal(`${next}-01`) }, status: { $in: ['confirmed', 'completed'] } }).select('mode').lean();
    months.push({ label: MON[dt.getUTCMonth()], value: l.length >= r.k ? pct(l.filter((a) => a.mode === 'online').length, l.length) : null });
  }
  const enough = held.length >= r.k;
  return { total: k(held.length, r.k), onlinePct: enough ? pct(online, held.length) : null, inPersonPct: enough ? 100 - pct(online, held.length) : null, months };
}

async function usage(r) {
  const appts = await Appointment.find({ start: { $gte: r.start, $lt: r.end }, status: { $in: ['confirmed', 'completed'] } }).select('student').lean();
  const ids = [...new Set(appts.map((a) => String(a.student)))];
  const students = await User.find({ _id: { $in: ids } }).select('faculty').lean();
  const byFac = {};
  for (const s of students) byFac[s.faculty || 'Other'] = (byFac[s.faculty || 'Other'] || 0) + 1;
  const faculties = Object.entries(byFac).sort((a, b) => b[1] - a[1]).map(([label, n]) => ({ label: label.replace('Faculty of ', ''), value: n >= r.k ? pct(n, students.length) : null, suppressed: n < r.k }));
  return { uniqueStudents: k(ids.length, r.k), sessionsPerStudent: ids.length >= r.k ? +(appts.length / ids.length).toFixed(1) : null, faculties };
}

async function wellness(r) {
  const ev = await WellnessEvent.find({ createdAt: { $gte: r.start, $lt: r.end } }).select('kind').lean();
  const c = (kind) => ev.filter((e) => e.kind === kind).length;
  const checkins = await MoodEntry.countDocuments({ date: { $gte: r.from, $lte: r.to } });
  const features = [
    { label: 'Mood check-ins', value: checkins }, { label: 'Articles read', value: c('article_read') },
    { label: 'Bridge chats', value: c('bridge_chat') }, { label: 'Breathing', value: c('breathing') },
    { label: 'Games', value: c('game') }, { label: 'Music', value: c('music') },
  ].map((f) => ({ ...f, value: k(f.value, r.k) }));
  // Safety signals are shown as totals even when small: they contain no identity.
  return { features, helplineTaps: c('helpline_tap'), escalations: c('bridge_escalation') };
}

async function users(r) {
  const counts = {};
  for (const role of ['student', 'counsellor', 'doctor', 'admin']) counts[role] = await User.countDocuments({ role, status: 'active' });
  const months = [];
  const now = T.todayStr();
  const [y, m] = now.split('-').map(Number);
  for (let i = 4; i >= 0; i--) {
    const dt = new Date(Date.UTC(y, m - 1 - i, 1));
    const nx = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth() + 1, 1));
    const n = await User.countDocuments({ role: 'student', createdAt: { $gte: T.fromLocal(dt.toISOString().slice(0, 10)), $lt: T.fromLocal(nx.toISOString().slice(0, 10)) } });
    months.push({ label: MON[dt.getUTCMonth()], value: k(n, r.k) });
  }
  return { counts, signups: months };
}

const SECTIONS = { overview, appointments, types, usage, wellness, users };

for (const [name, fn] of Object.entries(SECTIONS)) {
  router.get(`/${name}`, async (req, res) => {
    const r = await rangeOf(req);
    res.json({ range: { from: r.from, to: r.to, label: r.label }, minGroup: r.k, data: await fn(r) });
  });
}

// CSV or PDF export of the selected sections.
// Shared by the authenticated route and one-time download links.
async function sendExport(req, res) {
  const r = await rangeOf(req);
  const format = req.query.format === 'pdf' ? 'pdf' : 'csv';
  const wanted = String(req.query.sections || 'appointments,usage,wellness').split(',').filter((s) => SECTIONS[s] && s !== 'overview');
  if (!wanted.length) throw badRequest('Choose at least one section to export');
  const rows = [['Section', 'Metric', 'Value']];
  const v = (x) => (x === null || x === undefined ? `<${r.k} (hidden)` : String(x));
  const ov = await overview(r);
  rows.push(['Overview', 'Booking requests', v(ov.bookingRequests)], ['Overview', 'Students supported', v(ov.studentsSupported)], ['Overview', 'Online sessions %', v(ov.onlinePct)], ['Overview', 'Mood check-ins', v(ov.moodCheckins)]);
  for (const s of wanted) {
    const d = await SECTIONS[s](r);
    const title = { appointments: 'Appointments', usage: 'Counselling usage', wellness: 'Wellness usage', users: 'User statistics', types: 'Online vs in person' }[s];
    if (s === 'appointments') {
      rows.push([title, 'Requests', v(d.requests)], [title, 'Avg. hours to confirm', v(d.avgHoursToConfirm)], [title, 'Completed', v(d.completed)], [title, 'Duplicates flagged %', v(d.duplicatePct)]);
      d.outcomes.forEach((o) => rows.push([title, `Outcome: ${o.label}`, v(o.value)]));
    } else if (s === 'usage') {
      rows.push([title, 'Unique students', v(d.uniqueStudents)], [title, 'Sessions per student', v(d.sessionsPerStudent)]);
      d.faculties.forEach((f) => rows.push([title, `Faculty: ${f.label} %`, v(f.value)]));
    } else if (s === 'wellness') {
      d.features.forEach((f) => rows.push([title, f.label, v(f.value)]));
      rows.push([title, 'Helpline taps (1926)', String(d.helplineTaps)], [title, 'Bridge escalations', String(d.escalations)]);
    } else if (s === 'users') {
      Object.entries(d.counts).forEach(([role, n]) => rows.push([title, `Active ${role}s`, String(n)]));
    } else if (s === 'types') {
      rows.push([title, 'Online %', v(d.onlinePct)], [title, 'In person %', v(d.inPersonPct)]);
    }
  }
  await AuditLog.create({ actor: req.user._id, actorName: req.user.name, category: 'access', action: 'Report exported', target: `${format.toUpperCase()} · ${r.label}` });
  const fname = `mindbridge-report-${r.from}-to-${r.to}.${format}`;
  if (format === 'csv') {
    const esc = (c) => (/[",\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${fname}"`);
    return res.send(rows.map((row) => row.map(esc).join(',')).join('\n'));
  }
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${fname}"`);
  const doc = new PDFDocument({ margin: 48, size: 'A4' });
  doc.pipe(res);
  doc.fillColor('#2F5A3D').fontSize(20).text('MindBridge usage report');
  doc.moveDown(0.3).fillColor('#6E6A5D').fontSize(11).text(`${r.label} · anonymised · groups smaller than ${r.k} hidden`);
  doc.moveDown();
  let section = '';
  for (const row of rows.slice(1)) {
    if (row[0] !== section) {
      section = row[0];
      doc.moveDown(0.6).fillColor('#22261F').fontSize(13).text(section);
      doc.moveDown(0.2);
    }
    const y = doc.y;
    doc.fillColor('#45443A').fontSize(10.5).text(row[1], 60, y, { width: 330 });
    doc.fillColor('#22261F').text(row[2], 400, y, { width: 140, align: 'right' });
    doc.moveDown(0.25);
  }
  doc.moveDown().fillColor('#7A7567').fontSize(9).text('No session content, notes, check-ins or chats are included in this report.', 48);
  doc.end();
}

router.get('/export', sendExport);

module.exports = router;
module.exports.sendExport = sendExport;
