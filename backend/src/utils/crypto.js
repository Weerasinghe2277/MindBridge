// AES-256-GCM field encryption for the most sensitive data: session notes,
// clinical notes, journal entries, mood notes, booking notes and Bridge chats.
const crypto = require('crypto');
const env = require('../config/env');

const PREFIX = 'enc:v1:';

function encrypt(plain) {
  if (plain === undefined || plain === null || plain === '') return plain;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', env.dataKey, iv);
  const data = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return PREFIX + Buffer.concat([iv, tag, data]).toString('base64');
}

function decrypt(value) {
  if (typeof value !== 'string' || !value.startsWith(PREFIX)) return value;
  try {
    const raw = Buffer.from(value.slice(PREFIX.length), 'base64');
    const iv = raw.subarray(0, 12);
    const tag = raw.subarray(12, 28);
    const data = raw.subarray(28);
    const decipher = crypto.createDecipheriv('aes-256-gcm', env.dataKey, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  } catch {
    return '';
  }
}

// Mongoose field definition helper: stored encrypted, returned decrypted via getter.
const encryptedString = (extra = {}) => ({
  type: String,
  set: encrypt,
  get: decrypt,
  ...extra,
});

const randomCode = (digits = 6) => String(crypto.randomInt(0, 10 ** digits)).padStart(digits, '0');
const sha256 = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

module.exports = { encrypt, decrypt, encryptedString, randomCode, sha256 };
