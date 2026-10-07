const { Notification, AuditLog } = require('../models');

// Notification preference keys a user can switch off. Anything not listed is always delivered.
const PREF_FOR_TYPE = {
  booking_request: 'newRequests',
  duplicate: 'duplicateAlerts',
  reschedule: 'reschedules',
  cancel: 'reschedules',
  reminder: 'reminders',
  article: 'articleUpdates',
  referral: 'referralUpdates',
  checkin: 'checkinNudges',
};

async function notify(user, { type, title, body, icon, tone, link }) {
  if (!user) return null;
  const pref = PREF_FOR_TYPE[type];
  const prefs = user.notificationPrefs;
  if (pref && prefs && typeof prefs.get === 'function' && prefs.get(pref) === false) return null;
  const userId = user._id || user;
  return Notification.create({ user: userId, type, title, body, icon, tone, link });
}

async function audit(actor, category, action, target, detail) {
  return AuditLog.create({
    actor: actor?._id, actorName: actor ? `${actor.name}` : 'System', category, action, target, detail,
  });
}

module.exports = { notify, audit };
