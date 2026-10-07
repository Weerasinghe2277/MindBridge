// Single-file upload held in memory (never written to disk), then handed to services/storage.js.
//   router.post('/x', uploadOne({ types: AUDIO_TYPES, maxMb: 20, what: 'an MP3 or M4A file' }), handler)
// The file is in req.file (buffer, originalname, mimetype, size) and text fields in req.body.
const multer = require('multer');
const { badRequest } = require('../utils/errors');

const IMAGE_TYPES = { 'image/jpeg': /\.jpe?g$/i, 'image/png': /\.png$/i, 'image/webp': /\.webp$/i };
const AUDIO_TYPES = { 'audio/mpeg': /\.mp3$/i, 'audio/mp3': /\.mp3$/i, 'audio/mp4': /\.m4a$/i, 'audio/x-m4a': /\.m4a$/i, 'audio/aac': /\.aac$/i };

function uploadOne({ types, maxMb, what, field = 'file' }) {
  const mw = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxMb * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
      const ext = types[file.mimetype];
      const ok = !!ext && ext.test(file.originalname);
      cb(ok ? null : badRequest(`Upload ${what} up to ${maxMb} MB.`, 'BAD_FILE'), ok);
    },
  }).single(field);
  return (req, res, next) => mw(req, res, (err) => {
    if (err?.code === 'LIMIT_FILE_SIZE') return next(badRequest(`Upload ${what} up to ${maxMb} MB.`, 'BAD_FILE'));
    if (err) return next(err);
    if (!req.file) return next(badRequest(`Choose ${what} to upload.`, 'BAD_FILE'));
    next();
  });
}

module.exports = { uploadOne, IMAGE_TYPES, AUDIO_TYPES };
