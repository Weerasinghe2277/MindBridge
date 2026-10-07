// File storage. With CLOUDINARY_URL set, files go to Cloudinary; otherwise they are kept
// inside MongoDB (GridFS). Either way nothing is written to the server's disk, so files
// survive restarts on hosts with temporary file systems (e.g. Render).
//
// Two kinds of file:
//   saveFile / openFile / fileExists / deleteFile — PRIVATE files (staff credential documents).
//     Stored as Cloudinary "private" assets: no public URL, the API streams them to the
//     admin after its own access check.
//   saveMedia / deleteMedia — PUBLIC media (images, mp3 audio) that the app loads straight
//     from Cloudinary's CDN by URL. Requires Cloudinary.
const mongoose = require('mongoose');
const { Readable, PassThrough } = require('stream');
const cloudinary = require('cloudinary').v2;
const env = require('../config/env');
const { badRequest } = require('../utils/errors');

// ---------- Cloudinary ----------
const useCloudinary = (() => {
  if (!env.cloudinaryUrl) return false;
  const u = new URL(env.cloudinaryUrl); // cloudinary://<api_key>:<api_secret>@<cloud_name>
  cloudinary.config({
    cloud_name: u.hostname,
    api_key: decodeURIComponent(u.username),
    api_secret: decodeURIComponent(u.password),
    secure: true,
  });
  return true;
})();

// Cloudinary ids are stored as "cloudinary:<resource_type>:<format>:<public_id>" so they can sit
// next to older GridFS ids (plain ObjectIds) in the same field.
const PREFIX = 'cloudinary:';
const isCloud = (id) => String(id).startsWith(PREFIX);
function parseCloud(id) {
  const [resourceType, format, ...rest] = String(id).slice(PREFIX.length).split(':');
  return { resourceType, format, publicId: rest.join(':') };
}

function cloudUpload(buffer, options) {
  return new Promise((resolve, reject) => {
    const up = cloudinary.uploader.upload_stream(options, (err, result) => (err ? reject(err) : resolve(result)));
    Readable.from(buffer).pipe(up);
  });
}

// ---------- GridFS ----------
const bucket = () => new mongoose.mongo.GridFSBucket(mongoose.connection.db, { bucketName: 'documents' });

// ---------- Private files ----------
async function saveFile(buffer, filename, contentType) {
  if (useCloudinary) {
    const r = await cloudUpload(buffer, {
      folder: `${env.cloudinaryFolder}/documents`,
      type: 'private',
      resource_type: 'auto', // PDFs and photos are "image", anything else "raw"
      use_filename: false,
      context: { filename, contentType },
    });
    return `${PREFIX}${r.resource_type}:${r.format || ''}:${r.public_id}`;
  }
  return new Promise((resolve, reject) => {
    const up = bucket().openUploadStream(filename, { metadata: { contentType } });
    Readable.from(buffer).pipe(up).on('error', reject).on('finish', () => resolve(up.id.toString()));
  });
}

// Returns a readable stream of the file. Errors are emitted on the stream.
function openFile(id) {
  if (!isCloud(id)) return bucket().openDownloadStream(new mongoose.Types.ObjectId(id));
  const { resourceType, format, publicId } = parseCloud(id);
  // Short-lived signed link, used only by the server — the client never sees it.
  const url = cloudinary.utils.private_download_url(publicId, format, {
    resource_type: resourceType, type: 'private', expires_at: Math.floor(Date.now() / 1000) + 60,
  });
  const out = new PassThrough();
  fetch(url)
    .then((res) => {
      if (!res.ok) throw new Error(`Cloudinary download failed (${res.status})`);
      Readable.fromWeb(res.body).on('error', (e) => out.destroy(e)).pipe(out);
    })
    .catch((e) => out.destroy(e));
  return out;
}

async function fileExists(id) {
  if (isCloud(id)) {
    const { resourceType, publicId } = parseCloud(id);
    try {
      await cloudinary.api.resource(publicId, { resource_type: resourceType, type: 'private' });
      return true;
    } catch (e) {
      if (e?.error?.http_code === 404) return false;
      throw e;
    }
  }
  if (!mongoose.isValidObjectId(id)) return false;
  return (await bucket().find({ _id: new mongoose.Types.ObjectId(id) }).limit(1).toArray()).length > 0;
}

async function deleteFile(id) {
  try {
    if (isCloud(id)) {
      const { resourceType, publicId } = parseCloud(id);
      await cloudinary.uploader.destroy(publicId, { resource_type: resourceType, type: 'private', invalidate: true });
    } else {
      await bucket().delete(new mongoose.Types.ObjectId(id));
    }
  } catch {
    // already gone
  }
}

// ---------- Public media (images, audio) ----------
// kind: 'image' | 'audio'. Returns { id, url } — save both; show `url` in the app, pass `id` to deleteMedia.
async function saveMedia(buffer, { kind, folder = 'media' }) {
  if (!useCloudinary) throw badRequest('Media uploads need Cloudinary. Set CLOUDINARY_URL in backend/.env.', 'STORAGE_NOT_CONFIGURED');
  const r = await cloudUpload(buffer, {
    folder: `${env.cloudinaryFolder}/${folder}`,
    resource_type: kind === 'audio' ? 'video' : 'image', // Cloudinary keeps audio under "video"
  });
  return { id: `${PREFIX}${r.resource_type}:${r.format || ''}:${r.public_id}`, url: r.secure_url, durationSec: r.duration };
}

async function deleteMedia(id) {
  if (!isCloud(id)) return;
  const { resourceType, publicId } = parseCloud(id);
  try {
    await cloudinary.uploader.destroy(publicId, { resource_type: resourceType, invalidate: true });
  } catch {
    // already gone
  }
}

module.exports = { saveFile, openFile, fileExists, deleteFile, saveMedia, deleteMedia, useCloudinary };
