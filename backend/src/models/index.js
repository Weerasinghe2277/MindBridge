// Smaller shared models live together here; User and Appointment have their own files.
// Feature models owned by one team member live in src/modules/<feature>/ and are
// re-exported below so existing `require('../models')` imports keep working.
const mongoose = require('mongoose');
const { encryptedString } = require('../utils/crypto');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });



const ChatMessage = mongoose.model('ChatMessage', new Schema({
  student: ref('User', { required: true, index: true }),
  
  escalated: { type: Boolean, default: false },
}, opts));




const Otp = mongoose.model('Otp', new Schema({
  email: { type: String, required: true, lowercase: true, index: true },
  purpose: { type: String, enum: ['verify_email', 'reset_password', 'login_2fa'], required: true },
  codeHash: { type: String, required: true },
  attempts: { type: Number, default: 0 },
  expiresAt: { type: Date, required: true, index: { expires: 0 } },
}, opts));



const Setting = mongoose.model('Setting', new Schema({
  key: { type: String, unique: true, required: true },
  value: Schema.Types.Mixed,
}, { timestamps: true }));


module.exports = {
  MoodEntry, JournalEntry, Notification, Article, WellnessEvent, ChatMessage,
  SessionNote, Referral, Consultation, AuditLog, Otp, AuthSession, Setting, Track,
};
