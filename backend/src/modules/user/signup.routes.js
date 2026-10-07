// MEMBER 2 — User Management (CRUD 1): Sign Up. Mounted at /api/auth.
// The rate limiter for /register is applied in routes/auth.js, which is mounted first.
const express = require('express');
const env = require('../../config/env');
const User = require('../../models/User');
const { body, password, z } = require('../../middleware/validate');
const { createOtp } = require('../../services/otp');
const { getSettings } = require('../../services/settings');
const { audit, notify } = require('../../services/notify');
const { badRequest, conflict } = require('../../utils/errors');

const router = express.Router();

const email = z.string().trim().toLowerCase().email('Enter a valid email address');
const domainOf = (e) => e.split('@')[1] || '';

const registerSchema = z.object({
  role: z.enum(['student', 'counsellor', 'doctor']),
  name: z.string().trim().min(2, 'Enter your full name').max(80),
  email,
  password,
  studentId: z.string().trim().max(20).optional(),
  faculty: z.string().trim().max(80).optional(),
  year: z.number().int().min(1).max(6).optional(),
  phone: z.string().trim().max(20).optional(),
  professional: z.object({
    title: z.string().trim().max(80).optional(),
    qualifications: z.string().trim().max(300).optional(),
    registrationNo: z.string().trim().max(40).optional(),
    experienceYears: z.number().int().min(0).max(60).optional(),
  }).optional(),
  agreePrivacy: z.literal(true, { error: 'Please agree to the privacy policy' }),
});

// FR1 — register. Counsellor and doctor accounts start "pending" until Student Affairs verifies them (FR11).
router.post('/register', body(registerSchema), async (req, res) => {
  const b = req.body;
  const domain = domainOf(b.email);
  if (b.role === 'student') {
    if (!env.studentEmailDomains.includes(domain)) throw badRequest(`Use your university address (@${env.studentEmailDomains[0]})`, 'EMAIL_DOMAIN', { field: 'email' });
    if (!b.studentId || !/^[A-Z]{2}\d{8}$/i.test(b.studentId)) throw badRequest('Enter a valid student ID, e.g. IT23714052', 'VALIDATION_ERROR', { field: 'studentId' });
    if (!b.faculty) throw badRequest('Choose your faculty', 'VALIDATION_ERROR', { field: 'faculty' });
  } else {
    if (!env.staffEmailDomains.includes(domain)) throw badRequest(`Use your staff address (@${env.staffEmailDomains[0]})`, 'EMAIL_DOMAIN', { field: 'email' });
    if (!b.professional?.title || !b.professional?.registrationNo) throw badRequest('Add your professional title and registration number', 'VALIDATION_ERROR', { field: 'professional' });
  }
  const exists = await User.findOne({ email: b.email });
  if (exists) throw conflict('An account with this email already exists. Try signing in.', 'EMAIL_TAKEN', { field: 'email' });
  if (b.role === 'student' && await User.findOne({ studentId: b.studentId.toUpperCase() })) {
    throw conflict('This student ID is already registered.', 'STUDENT_ID_TAKEN', { field: 'studentId' });
  }

  const user = new User({
    role: b.role, name: b.name, email: b.email, phone: b.phone,
    studentId: b.role === 'student' ? b.studentId : undefined,
    faculty: b.faculty, year: b.year,
  });
  if (b.role !== 'student') {
    const settings = await getSettings();
    user.professional = { ...b.professional, languages: ['English'], focusAreas: [], modes: ['online', 'in_person'] };
    user.availability = { sessionLength: settings.appointments.defaultSessionLength };
    user.verification = { status: 'pending', submittedAt: new Date(), history: [{ label: 'Application submitted', at: new Date() }] };
  }
  await user.setPassword(b.password);
  await user.save();
  if (b.role !== 'student') {
    const admins = await User.find({ role: 'admin', status: 'active' });
    await Promise.all(admins.map((a) => notify(a, { type: 'verification', title: `New ${b.role} application`, body: b.name, icon: 'person_add', tone: 'blue', link: { screen: 'verification', id: user.id } })));
    await audit(user, 'verification', `New ${b.role} application`, b.name);
  }
  const dev = await createOtp(user.email, 'verify_email');
  res.status(201).json({ email: user.email, needsVerification: true, ...dev });
});

module.exports = router;
