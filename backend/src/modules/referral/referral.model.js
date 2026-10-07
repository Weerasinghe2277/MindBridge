const mongoose = require('mongoose');
const { encryptedString } = require('../../utils/crypto');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });

const Referral = mongoose.model('Referral', new Schema({
  counsellor: ref('User', { required: true, index: true }),
  doctor: ref('User', { required: true, index: true }),
  student: ref('User', { required: true, index: true }),
  appointment: ref('Appointment'),
  urgency: { type: String, enum: ['routine', 'priority', 'urgent'], default: 'routine' },
  reason: encryptedString({ required: true }),
  share: {
    summary: { type: Boolean, default: true },
    contact: { type: Boolean, default: true },
    fullNotes: { type: Boolean, default: false },
  },
  summary: encryptedString(),
  contact: encryptedString(),
  consent: { type: Boolean, required: true },
  status: { type: String, enum: ['new', 'accepted', 'declined'], default: 'new', index: true },
  decline: { reason: String, note: String },
  infoRequests: [{ items: [String], message: String, reply: String, at: Date, repliedAt: Date }],
  consultation: ref('Consultation'),
}, opts));

module.exports = Referral;
