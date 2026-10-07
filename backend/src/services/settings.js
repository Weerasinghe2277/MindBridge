// System-wide settings managed by admins (M3-46 … M3-49).
const { Setting } = require('../models');

const DEFAULTS = {
  appointments: {
    defaultSessionLength: 30,
    bookingWindowDays: 21,
    minCancelNoticeHours: 2,
    blockDuplicateBookings: true, // FR7
    allowOnline: true,
    allowInPerson: true,
    autoCancelUnconfirmedHours: 48,
    autoCancelEnabled: true,
  },
  notifications: {
    reminderDay: true,
    reminderHour: true,
    dailyCheckinNudge: true,
    counsellorRequestAlerts: true,
    duplicateAlerts: true,
  },
  privacy: {
    minReportGroupSize: 10, // locked by policy
    sessionNoteRetentionYears: 5,
    autoDeleteBridgeChats: true,
    bridgeChatRetentionDays: 30,
    showHelplineEverywhere: true,
  },
  security: {
    staffTwoFactor: false, // admins always use two-factor
    autoSignOutMinutes: 15,
    passwordPolicy: '8+ characters with a number',
  },
};

let cache = null;

async function getSettings() {
  if (cache) return cache;
  const doc = await Setting.findOne({ key: 'system' }).lean();
  const v = doc?.value || {};
  cache = Object.fromEntries(Object.entries(DEFAULTS).map(([k, d]) => [k, { ...d, ...(v[k] || {}) }]));
  return cache;
}

async function updateSettings(section, patch) {
  const current = await getSettings();
  if (!DEFAULTS[section]) throw new Error('Unknown settings section');
  const allowed = Object.keys(DEFAULTS[section]);
  const clean = {};
  for (const [k, val] of Object.entries(patch || {})) {
    if (!allowed.includes(k)) continue;
    if (typeof val !== typeof DEFAULTS[section][k]) continue;
    clean[k] = val;
  }
  // Privacy policy floor that can't be lowered from the app.
  if (section === 'privacy') delete clean.minReportGroupSize;
  const next = { ...current, [section]: { ...current[section], ...clean } };
  await Setting.findOneAndUpdate({ key: 'system' }, { value: next }, { upsert: true });
  cache = next;
  return { next, changed: Object.keys(clean) };
}

const resetCache = () => { cache = null; };

module.exports = { getSettings, updateSettings, DEFAULTS, resetCache };
