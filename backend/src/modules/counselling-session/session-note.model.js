const mongoose = require('mongoose');
const { encryptedString } = require('../../utils/crypto');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });

const SessionNote = mongoose.model('SessionNote', new Schema({
  appointment: ref('Appointment', { required: true, unique: true }),
  counsellor: ref('User', { required: true, index: true }),
  student: ref('User', { required: true, index: true }),
  summary: encryptedString(),
  plan: encryptedString(),
  tags: [String],
  goals: [{ text: String, done: Boolean }],
  recommendReferral: { type: Boolean, default: false },
}, opts));

module.exports = SessionNote;
