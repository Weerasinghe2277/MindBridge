const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const { Schema } = mongoose;

const ROLES = ['student', 'counsellor', 'doctor', 'admin'];
const VERIFICATION = ['not_required', 'pending', 'changes_requested', 'approved', 'rejected'];

const BlockSchema = new Schema({
  date: { type: String, required: true }, // YYYY-MM-DD local
  from: { type: String, default: '00:00' },
  to: { type: String, default: '23:59' },
  allDay: { type: Boolean, default: false },
  reason: { type: String, default: '' },
  repeatWeekly: { type: Boolean, default: false },
}, { _id: true });

// Weekly schedule used to generate bookable slots for counsellors and doctors.
const AvailabilitySchema = new Schema({
  workingDays: { type: [Number], default: [1, 2, 3, 4, 5] }, // ISO weekday Mon=1..Sun=7
  startTime: { type: String, default: '09:00' },
  endTime: { type: String, default: '16:30' },
  lunchBreak: {
    enabled: { type: Boolean, default: true },
    start: { type: String, default: '12:30' },
    end: { type: String, default: '13:30' },
  },
  sessionLength: { type: Number, default: 30, enum: [30, 45, 60] },
  bufferMinutes: { type: Number, default: 0, enum: [0, 5, 10, 15] },
  blocks: { type: [BlockSchema], default: [] },
}, { _id: false });

const DocumentSchema = new Schema({
  label: { type: String, required: true }, // e.g. "Degree certificate"
  fileName: String,
  storedName: String,
  mimeType: String,
  size: Number,
  checked: { type: Boolean, default: false },
  uploadedAt: { type: Date, default: Date.now },
});

const UserSchema = new Schema({
  name: { type: String, required: true, trim: true },
  preferredName: { type: String, trim: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  passwordHash: { type: String, required: true, select: false },
  role: { type: String, enum: ROLES, required: true, index: true },
  status: { type: String, enum: ['active', 'deactivated'], default: 'active' },
  statusReason: String,
  emailVerified: { type: Boolean, default: false },
  phone: String,
  language: { type: String, default: 'English' },
  gender: { type: String, enum: ['female', 'male', 'other', ''], default: '' },

  // Student fields
  studentId: { type: String, trim: true, uppercase: true },
  faculty: String,
  year: Number,

  privacy: {
    shareMoodTrends: { type: Boolean, default: false },
    biometricUnlock: { type: Boolean, default: false },
    hidePreviews: { type: Boolean, default: true },
  },
  notificationPrefs: { type: Map, of: Boolean, default: {} },
  savedArticles: [{ type: Schema.Types.ObjectId, ref: 'Article' }],
  favoriteCounsellors: [{ type: Schema.Types.ObjectId, ref: 'User' }],

  // Staff professional profile (counsellor / doctor)
  professional: {
    title: String, // "Clinical Psychologist", "Medical Officer"
    qualifications: String,
    about: String,
    focusAreas: [String],
    languages: [String],
    experienceYears: Number,
    registrationNo: String, // SLPA / SLNCC / SLMC
    renewalDue: String,
    modes: { type: [String], default: ['online', 'in_person'] },
    room: String,
    office: String,
    extension: String,
  },
  availability: { type: AvailabilitySchema, default: undefined },

  verification: {
    status: { type: String, enum: VERIFICATION, default: 'not_required' },
    submittedAt: Date,
    reviewedAt: Date,
    reviewedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    note: String,
    reason: String,
    requestedItems: [String],
    documents: [DocumentSchema],
    history: [{ label: String, at: Date }],
  },
  lastActiveAt: Date,
}, { timestamps: true, toJSON: { getters: true } });

UserSchema.index({ name: 'text', email: 'text', studentId: 'text' });

UserSchema.methods.setPassword = async function setPassword(pw) {
  this.passwordHash = await bcrypt.hash(pw, 12);
};
UserSchema.methods.checkPassword = function checkPassword(pw) {
  return bcrypt.compare(pw, this.passwordHash);
};

UserSchema.virtual('initials').get(function initials() {
  const parts = (this.name || '').replace(/^(Dr|Mr|Ms|Mrs|Prof)\.?\s+/i, '').split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] || '') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
});

UserSchema.virtual('isStaff').get(function isStaff() {
  return this.role === 'counsellor' || this.role === 'doctor';
});

// Public-safe representation. Never exposes the password hash.
UserSchema.methods.toPublic = function toPublic() {
  const o = {
    id: this._id.toString(),
    name: this.name,
    preferredName: this.preferredName || this.name.split(' ')[0],
    email: this.email,
    role: this.role,
    status: this.status,
    emailVerified: this.emailVerified,
    initials: this.initials,
    phone: this.phone || '',
    language: this.language,
    gender: this.gender || '',
    createdAt: this.createdAt,
    lastActiveAt: this.lastActiveAt,
  };
  if (this.role === 'student') {
    Object.assign(o, {
      studentId: this.studentId, faculty: this.faculty, year: this.year,
      privacy: this.privacy, savedArticles: (this.savedArticles || []).map(String),
      favoriteCounsellors: (this.favoriteCounsellors || []).map(String),
    });
  }
  if (this.role !== 'student') {
    o.professional = this.professional || {};
  }
  if (this.isStaff) {
    o.verification = {
      status: this.verification?.status,
      submittedAt: this.verification?.submittedAt,
      reviewedAt: this.verification?.reviewedAt,
      note: this.verification?.note,
      reason: this.verification?.reason,
      requestedItems: this.verification?.requestedItems || [],
      history: this.verification?.history || [],
      documents: (this.verification?.documents || []).map((d) => ({
        id: d._id.toString(), label: d.label, fileName: d.fileName, size: d.size, mimeType: d.mimeType, checked: d.checked, uploadedAt: d.uploadedAt,
      })),
    };
    o.availability = this.availability || null;
  }
  o.notificationPrefs = Object.fromEntries(this.notificationPrefs || []);
  return o;
};

module.exports = mongoose.model('User', UserSchema);
module.exports.ROLES = ROLES;
