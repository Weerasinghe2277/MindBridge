
const express = require('express');
const env = require('../../config/env');
const User = require('../../models/User');
const { body, password, z } = require('../../middleware/validate');


// FR1 — register. Counsellor and doctor accounts start "pending" until Student Affairs verifies them (FR11).
router.post('/register', body(registerSchema), async (req, res) => {
  const b = req.body;
  const domain = domainOf(b.email);

  const exists = await User.findOne({ email: b.email });
  if (exists) throw conflict('An account with this email already exists. Try signing in.', 'EMAIL_TAKEN', { field: 'email' });
  if (b.role === 'student' && await User.findOne({ studentId: b.studentId.toUpperCase() })) {
    throw conflict('This student ID is already registered.', 'STUDENT_ID_TAKEN', { field: 'studentId' });
  }



module.exports = router;
