// Background jobs: appointment reminders (FR5), auto-cancel of stale requests
// and Bridge chat retention (privacy setting). Runs every minute.
const Appointment = require('../models/Appointment');
const User = require('../models/User');
const { ChatMessage, MoodEntry, Notification } = require('../models');
const { notify } = require('./notify');
const { getSettings } = require('./settings');
const T = require('../utils/time');

const HOUR = 3600 * 1000;

async function sendReminders(settings) {
  const now = Date.now();
  const due = await Appointment.find({
    status: 'confirmed', remindersOn: true, start: { $gt: new Date(now), $lte: new Date(now + 24 * HOUR) },
    $or: [{ 'remindersSent.day': false }, { 'remindersSent.hour': false }],
  }).populate('student', 'name notificationPrefs').populate('counsellor', 'name notificationPrefs');
  for (const a of due) {
    const left = a.start.getTime() - now;
    const where = a.mode === 'online' ? 'Online · link opens 10 min before' : a.location;
    if (left <= HOUR && !a.remindersSent.hour && settings.notifications.reminderHour) {
      await notify(a.student, { type: 'reminder', title: 'Your session starts within the hour', body: `${a.counsellor.name} · ${T.fmtTime(a.start)} · ${where}`, icon: 'alarm', tone: 'blue', link: { screen: 'appointment', id: a.id } });
      await notify(a.counsellor, { type: 'reminder', title: 'Session soon', body: `${a.student.name} · ${T.fmtTime(a.start)}`, icon: 'alarm', tone: 'blue', link: { screen: 'appointment', id: a.id } });
      a.remindersSent.hour = true;
      a.remindersSent.day = true;
    } else if (left > HOUR && !a.remindersSent.day && settings.notifications.reminderDay) {
      await notify(a.student, { type: 'reminder', title: 'Reminder: session tomorrow', body: `${a.counsellor.name} · ${T.fmtDateTime(a.start)} · ${where}`, icon: 'alarm', tone: 'blue', link: { screen: 'appointment', id: a.id } });
      a.remindersSent.day = true;
    } else {
      continue;
    }
    await a.save();
  }
}

async function autoCancel(settings) {
  const { autoCancelEnabled, autoCancelUnconfirmedHours } = settings.appointments;
  const now = new Date();
  // Requests whose time has passed without a decision are always closed.
  const stale = await Appointment.find({
    status: 'pending',
    $or: [
      { start: { $lte: now } },
      ...(autoCancelEnabled ? [{ createdAt: { $lte: new Date(now - autoCancelUnconfirmedHours * HOUR) } }] : []),
    ],
  }).populate('student', 'name notificationPrefs');
  for (const a of stale) {
    a.status = 'cancelled';
    a.slotLock = false;
    a.cancel = { reason: 'Not confirmed in time', by: 'system', at: now };
    a.history.push({ status: 'cancelled', label: 'Cancelled automatically — not confirmed in time', by: 'system' });
    await a.save();
    await notify(a.student, { type: 'booking', title: 'Request expired', body: `Your request for ${T.fmtDateTime(a.start)} wasn’t confirmed in time, so the slot was released. You can book another time.`, icon: 'event_busy', tone: 'amber', link: { screen: 'appointment', id: a.id } });
  }
}

async function retention(settings) {
  const { autoDeleteBridgeChats, bridgeChatRetentionDays } = settings.privacy;
  if (autoDeleteBridgeChats) await ChatMessage.deleteMany({ createdAt: { $lt: new Date(Date.now() - bridgeChatRetentionDays * 24 * HOUR) } });
  await Notification.deleteMany({ createdAt: { $lt: new Date(Date.now() - 90 * 24 * HOUR) } });
}

let lastNudgeDate = null;
// Daily check-in nudge at 7 PM local time for students who haven't checked in (FR9, optional).
async function checkinNudge(settings) {
  if (!settings.notifications.dailyCheckinNudge) return;
  const l = T.local(new Date());
  if (l.hh !== 19 || lastNudgeDate === l.dateStr) return;
  lastNudgeDate = l.dateStr;
  const done = new Set((await MoodEntry.distinct('student', { date: l.dateStr })).map(String));
  const students = await User.find({ role: 'student', status: 'active', emailVerified: true }).select('notificationPrefs');
  for (const s of students) {
    if (done.has(s.id)) continue;
    await notify(s, { type: 'checkin', title: 'Daily check-in', body: 'Take 30 seconds to note how you’re feeling.', icon: 'self_improvement', tone: 'lilac', link: { screen: 'checkin' } });
  }
}

async function tick() {
  try {
    const settings = await getSettings();
    await sendReminders(settings);
    await autoCancel(settings);
    await retention(settings);
    await checkinNudge(settings);
  } catch (e) {
    console.error('[scheduler]', e.message);
  }
}

function startScheduler() {
  tick();
  return setInterval(tick, 60 * 1000);
}

module.exports = { startScheduler, tick };
