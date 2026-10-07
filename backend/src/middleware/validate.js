const { z } = require('zod');
const { badRequest } = require('../utils/errors');

// Validates and replaces req.body with the parsed, typed result.
const body = (schema) => (req, _res, next) => {
  const r = schema.safeParse(req.body ?? {});
  if (!r.success) {
    const first = r.error.issues[0];
    const field = first.path.join('.');
    throw badRequest(first.message, 'VALIDATION_ERROR', { field, issues: r.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message })) });
  }
  req.body = r.data;
  next();
};

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid id');
const password = z.string()
  .min(8, 'Use at least 8 characters')
  .max(128)
  .regex(/\d/, 'Include at least one number');

// Strips Mongo operators from any user-supplied object (defence against NoSQL injection).
function sanitize(req, _res, next) {
  const clean = (v) => {
    if (Array.isArray(v)) return v.map(clean);
    if (v && typeof v === 'object') {
      for (const k of Object.keys(v)) {
        if (k.startsWith('$') || k.includes('.')) delete v[k];
        else v[k] = clean(v[k]);
      }
    }
    return v;
  };
  if (req.body) clean(req.body);
  next();
}

const isValidId = (s) => typeof s === 'string' && /^[a-f\d]{24}$/i.test(s);

module.exports = { body, objectId, password, sanitize, isValidId, z };
