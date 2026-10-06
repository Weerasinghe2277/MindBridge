const mongoose = require('mongoose');
const { encryptedString } = require('../utils/crypto');

const { Schema } = mongoose;

// pending               – student requested, waiting for counsellor (FR4)

const STATUSES = ['pending', 'confirmed', 'reschedule_requested', 'reschedule_proposed', 'declined', 'cancelled', 'completed', 'no_show'];
const ACTIVE = ['pending', 'confirmed', 'reschedule_requested', 'reschedule_proposed'];

const HistorySchema = new Schema({
  status: String,
  label: String,
  by: { type: String, enum: ['student', 'counsellor', 'system', 'admin'] },
  at: { type: Date, default: Date.now },
}, { _id: false });

const AppointmentSchema = new Schema({
  reference: { type: String, unique: true },
  student: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  counsellor: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  start: { type: Date, required: true },
  end: { type: Date, required: true },
  mode: { type: String, enum: ['online', 'in_person'], required: true },
  location: String,
  meetingLink: String,
  note: encryptedString(), // visible to the counsellor only
  status: { type: String, enum: STATUSES, default: 'pending', index: true },
  // Holds the slot while the booking is active. A partial unique index on
  // (counsellor, start, slotLock) makes double-booking a slot impossible even under races.
  slotLock: { type: Boolean, default: true },
  duplicateOf: [{ type: Schema.Types.ObjectId, ref: 'Appointment' }],
  flaggedDuplicate: { type: Boolean, default: false }, // kept for reporting after the flag is resolved
  proposal: {
    start: Date,
    end: Date,
    reason: String,
    by: { type: String, enum: ['student', 'counsellor'] },
    at: Date,
  },
);

// Human-friendly booking reference (e.g. MB-20481) from an atomic counter, so it is always unique.
AppointmentSchema.pre('validate', async function setReference() {
  if (this.reference) return;
  const counter = await mongoose.connection.collection('settings').findOneAndUpdate(
    { key: 'appointmentSeq' },
    { $inc: { value: 1 } },
    { upsert: true, returnDocument: 'after' },
  );
  this.reference = `MB-${20000 + Number(counter.value)}`;
});



module.exports = mongoose.model('Appointment', AppointmentSchema);
module.exports.STATUSES = STATUSES;
module.exports.ACTIVE = ACTIVE;
