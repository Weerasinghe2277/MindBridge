const mongoose = require('mongoose');

const { Schema } = mongoose;
const opts = { timestamps: true, toJSON: { getters: true } };
const ref = (model, extra = {}) => ({ type: Schema.Types.ObjectId, ref: model, ...extra });

const Article = mongoose.model('Article', new Schema({
  author: ref('User', { required: true, index: true }),
  title: { type: String, required: true },
  category: { type: String, required: true },
  body: { type: String, required: true },
  status: { type: String, enum: ['draft', 'in_review', 'published', 'rejected', 'removed'], default: 'draft', index: true },
  // Edits to a live article wait here for review; the published text stays visible meanwhile.
  revision: { title: String, category: String, body: String, submittedAt: Date },
  review: { reason: String, feedback: String, by: ref('User'), at: Date },
  // Optional cover image, stored in Cloudinary (services/storage.js saveMedia).
  cover: { id: String, url: String },
  reads: { type: Number, default: 0 },
  submittedAt: Date,
  publishedAt: Date,
}, opts));

module.exports = Article;
