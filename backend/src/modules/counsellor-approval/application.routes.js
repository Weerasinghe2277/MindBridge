// MEMBER 2 — Counsellor Approval (CRUD 2), applicant side. Mounted at /api/me.
// Counsellor/doctor applications: upload and remove credential documents, resubmit (FR11).
const express = require('express');
const multer = require('multer');
const User = require('../../models/User');
const { requireAuth } = require('../../middleware/auth');
const { body, z } = require('../../middleware/validate');
const { audit, notify } = require('../../services/notify');
const storage = require('../../services/storage');
const { badRequest, notFound, conflict } = require('../../utils/errors');

const router = express.Router();
router.use(requireAuth);

// ---------- Staff credential documents (FR11) ----------
// Files are held in memory (max 5 MB) and then written to MongoDB GridFS.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = ['application/pdf', 'image/jpeg', 'image/png'].includes(file.mimetype) && /\.(pdf|jpe?g|png)$/i.test(file.originalname);
    cb(ok ? null : badRequest('Upload a PDF, JPG or PNG up to 5 MB.', 'BAD_FILE'), ok);
  },
});

router.post('/documents', upload.single('file'), async (req, res) => {
  if (!req.user.isStaff) throw badRequest('Only counsellors and doctors upload credentials.');
  if (!req.file) throw badRequest('Choose a file to upload.', 'BAD_FILE');
  const label = String(req.body.label || 'Document').slice(0, 60);
  const u = await User.findById(req.user._id);
  // Replace a document with the same label (e.g. a clearer scan).
  const old = u.verification.documents.find((d) => d.label === label);
  if (old) { await storage.deleteFile(old.storedName); old.deleteOne(); }
  const fileId = await storage.saveFile(req.file.buffer, req.file.originalname, req.file.mimetype);
  u.verification.documents.push({ label, fileName: req.file.originalname, storedName: fileId, mimeType: req.file.mimetype, size: req.file.size });
  await u.save();
  res.status(201).json({ user: u.toPublic() });
});

router.delete('/documents/:docId', async (req, res) => {
  const u = await User.findById(req.user._id);
  const d = u.verification?.documents?.id(req.params.docId);
  if (!d) throw notFound('Document not found.');
  if (u.verification.status === 'approved') throw conflict('Verified documents can’t be removed.', 'LOCKED');
  await storage.deleteFile(d.storedName);
  d.deleteOne();
  await u.save();
  res.json({ user: u.toPublic() });
});

router.post('/verification/resubmit', body(z.object({ note: z.string().trim().max(500).optional() })), async (req, res) => {
  const u = await User.findById(req.user._id);
  if (!u.isStaff) throw badRequest('Only staff accounts are verified.');
  if (!['changes_requested', 'rejected'].includes(u.verification.status)) throw conflict('Your application is already being reviewed.', 'STATE_CHANGED');
  if (!u.verification.documents.length) throw badRequest('Upload at least one document first.', 'NO_DOCUMENTS');
  u.verification.status = 'pending';
  u.verification.submittedAt = new Date();
  u.verification.requestedItems = [];
  u.verification.history.push({ label: 'Application resubmitted', at: new Date() });
  await u.save();
  const admins = await User.find({ role: 'admin', status: 'active' });
  await Promise.all(admins.map((a) => notify(a, { type: 'verification', title: 'Application resubmitted', body: u.name, icon: 'person_add', tone: 'blue', link: { screen: 'verification', id: u.id } })));
  await audit(u, 'verification', 'Application resubmitted', u.name);
  res.json({ user: u.toPublic() });
});

module.exports = router;
