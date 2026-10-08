// Smaller shared models live together here; User and Appointment have their own files.
// Feature models owned by one team member live in src/modules/<feature>/ and are
// re-exported below so existing `require('../models')` imports keep working.
const mongoose = require('mongoose');
const { encryptedString } = require('../utils/crypto');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });

const JournalEntry = mongoose.model('JournalEntry', new Schema({
  student: ref('User', { required: true, index: true }),
  title: encryptedString(),
  body: encryptedString(),
  mood: { type: Number, min: 0, max: 4 },
  tags: [String],
}, opts));

const Notification = mongoose.model('Notification', new Schema({
  user: ref('User', { required: true, index: true }),
  type: String,
  title: String,
  body: String,
  icon: { type: String, default: 'notifications' },
  tone: { type: String, default: 'green' },
  link: { screen: String, id: String },
  read: { type: Boolean, default: false, index: true },
}, opts));

// Wellness feature usage — feeds the student's own stats and anonymised admin reports (FR12).
const WellnessEvent = mongoose.model('WellnessEvent', new Schema({
  user: ref('User', { index: true }),
  kind: { type: String, enum: ['breathing', 'game', 'music', 'article_read', 'helpline_tap', 'bridge_chat', 'bridge_escalation'], required: true },
  detail: String,
  durationSec: Number,
}, opts));

const ChatMessage = mongoose.model('ChatMessage', new Schema({
  student: ref('User', { required: true, index: true }),
  from: { type: String, enum: ['me', 'ai'], required: true },
  text: encryptedString({ required: true }),
  escalated: { type: Boolean, default: false },
}, opts));

const Consultation = mongoose.model('Consultation', new Schema({
  doctor: ref('User', { required: true, index: true }),
  student: ref('User', { required: true, index: true }),
  referral: ref('Referral'),
  followUpOf: ref('Consultation'),
  start: { type: Date, required: true },
  end: { type: Date, required: true },
  mode: { type: String, enum: ['online', 'in_person'], default: 'in_person' },
  room: String,
  status: { type: String, enum: ['scheduled', 'in_progress', 'completed', 'cancelled'], default: 'scheduled', index: true },
  startedAt: Date,
  endedAt: Date,
  vitals: { bloodPressure: String, avgSleep: String },
  assessment: encryptedString(),
  tags: [String],
  clinicalNotes: encryptedString(),
  plan: encryptedString(),
  shareSummary: { type: Boolean, default: true },
  notifyCounsellor: { type: Boolean, default: true },
}, opts));

// Relaxing music in the Wellness hub. Audio files live in Cloudinary (services/storage.js);
// a track without audio plays as a timed demo in the app.
const TRACK_CATEGORIES = ['Sleep', 'Focus', 'Rain', 'Nature', 'Lo-fi'];
const Track = mongoose.model('Track', new Schema({
  title: { type: String, required: true },
  artist: { type: String, default: '' },
  category: { type: String, enum: TRACK_CATEGORIES, required: true },
  seconds: { type: Number, default: 0 },
  icon: { type: String, default: 'music_note' },
  tone: { type: String, default: 'green' },
  audio: { id: String, url: String },
  addedBy: ref('User'),
}, opts));
Track.CATEGORIES = TRACK_CATEGORIES;

const AuditLog = mongoose.model('AuditLog', new Schema({
  actor: ref('User'),
  actorName: String,
  category: { type: String, enum: ['users', 'verification', 'articles', 'music', 'settings', 'access', 'auth'], index: true },
  action: String,
  target: String,
  detail: String,
}, opts));

const Otp = mongoose.model('Otp', new Schema({
  email: { type: String, required: true, lowercase: true, index: true },
  purpose: { type: String, enum: ['verify_email', 'reset_password', 'login_2fa'], required: true },
  codeHash: { type: String, required: true },
  attempts: { type: Number, default: 0 },
  expiresAt: { type: Date, required: true, index: { expires: 0 } },
}, opts));

// Server-side sessions let us enforce inactivity sign-out (NFR4), list active
// admin sessions and revoke tokens on sign-out or password change.
const AuthSession = mongoose.model('AuthSession', new Schema({
  user: ref('User', { required: true, index: true }),
  jti: { type: String, required: true, unique: true },
  device: String,
  lastSeenAt: { type: Date, default: Date.now },
  revoked: { type: Boolean, default: false },
  expiresAt: { type: Date, index: { expires: 0 } },
}, opts));

// Quick unlock (fingerprint, face or screen lock): one long random key per phone. The phone keeps
// the key in its secure storage and only releases it after the user passes the device lock; the
// server stores just a hash and swaps in a new key on every use.
const QuickUnlockKey = mongoose.model('QuickUnlockKey', new Schema({
  user: ref('User', { required: true, index: true }),
  keyHash: { type: String, required: true, unique: true },
  device: String,
  lastUsedAt: Date,
  expiresAt: { type: Date, required: true, index: { expires: 0 } },
}, opts));

const Setting = mongoose.model('Setting', new Schema({
  key: { type: String, unique: true, required: true },
  value: Schema.Types.Mixed,
}, { timestamps: true }));

const MoodEntry = require('../modules/mood/mood.model');
const Article = require('../modules/article/article.model');
const SessionNote = require('../modules/counselling-session/session-note.model');
const Referral = require('../modules/referral/referral.model');

module.exports = {
  MoodEntry, JournalEntry, Notification, Article, WellnessEvent, ChatMessage,
  SessionNote, Referral, Consultation, AuditLog, Otp, AuthSession, QuickUnlockKey, Setting, Track,
};
