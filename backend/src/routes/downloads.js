// One-time download links (valid 2 minutes) so the app can open report exports and
// credential documents in the browser without ever putting a session token in a URL.
const express = require('express');
const crypto = require('crypto');
const User = require('../models/User');
const { requireAuth, requireRole } = require('../middleware/auth');
const { body, z, objectId } = require('../middleware/validate');
const { notFound, badRequest } = require('../utils/errors');

const links = new Map(); // token -> { adminId, target, query, ownerId, docId, expires }
const TTL = 2 * 60 * 1000;

const router = express.Router();

router.post('/', requireAuth, requireRole('admin'), body(z.object({
  target: z.enum(['report', 'document']),
  query: z.record(z.string(), z.string()).optional().default({}),
  ownerId: objectId.optional(),
  docId: objectId.optional(),
})), (req, res) => {
  if (req.body.target === 'document' && !(req.body.ownerId && req.body.docId)) throw badRequest('Missing document');
  for (const [k, v] of links) if (v.expires < Date.now()) links.delete(k);
  const token = crypto.randomBytes(24).toString('base64url');
  links.set(token, { adminId: req.user._id, ...req.body, expires: Date.now() + TTL });
  res.status(201).json({ path: `/api/download/${token}` });
});

router.get('/:token', async (req, res) => {
  const link = links.get(req.params.token);
  links.delete(req.params.token); // single use
  if (!link || link.expires < Date.now()) throw notFound('This download link has expired. Go back to MindBridge and try again.');
  const admin = await User.findById(link.adminId);
  if (!admin || admin.role !== 'admin' || admin.status !== 'active') throw notFound();
  const fakeReq = { user: admin, query: link.query };
  if (link.target === 'report') return require('./reports').sendExport(fakeReq, res);
  return require('../modules/counsellor-approval/approval.routes').sendDocument(fakeReq, res, String(link.ownerId), String(link.docId));
});

module.exports = router;
