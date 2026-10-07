const mongoose = require('mongoose');
const { encryptedString } = require('../../utils/crypto');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });

// FR9 — optional daily mood check-in. Mood scale 0 (Awful) … 4 (Great).
const MoodEntry = mongoose.model('MoodEntry', new Schema({
  student: ref('User', { required: true, index: true }),
  mood: { type: Number, min: 0, max: 4, required: true },
  factors: [String],
  note: encryptedString(),
  date: { type: String, required: true, index: true }, // local YYYY-MM-DD
  source: { type: String, default: 'checkin' }, // checkin | game | journal
}, opts));

module.exports = MoodEntry;
