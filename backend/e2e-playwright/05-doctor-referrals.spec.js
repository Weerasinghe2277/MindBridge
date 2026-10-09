const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('05 - Doctor Referrals & Medical Consultations', () => {
  let counsellorToken;
  let doctorToken;
  let adminToken;

  test.beforeAll(async ({ request }) => {
    counsellorToken = await getRoleToken(request, 'counsellor');
    doctorToken = await getRoleToken(request, 'doctor');
    adminToken = await getRoleToken(request, 'admin');
  });

  test('Medical referral workflow: consent validation, selective sharing, and consultation lifecycle', async ({ request }) => {
    // 1. Get completed appointment and doctor list
    const pastRes = await request.get('/api/appointments?scope=past', { headers: authHeader(counsellorToken) });
    expect(pastRes.status()).toBe(200);
    const pastAppt = (await pastRes.json()).appointments.find((a) => a.status === 'completed');
    expect(pastAppt).toBeDefined();

    const docsRes = await request.get('/api/staff/doctors', { headers: authHeader(counsellorToken) });
    expect(docsRes.status()).toBe(200);
    const doctors = (await docsRes.json()).doctors;
    expect(doctors.length).toBeGreaterThanOrEqual(1);
    const doctor = doctors[0];

    // 2. Enforce patient consent: referral without consent returns 400
    const noConsentRes = await request.post('/api/referrals', {
      headers: authHeader(counsellorToken),
      data: {
        appointmentId: pastAppt.id,
        doctorId: doctor.id,
        urgency: 'routine',
        reason: 'Recurrent migraine symptoms during exam periods',
        share: { summary: true, contact: false },
        consent: false,
      },
    });
    expect(noConsentRes.status()).toBe(400);

    // 3. Referral with consent succeeds
    const referralRes = await request.post('/api/referrals', {
      headers: authHeader(counsellorToken),
      data: {
        appointmentId: pastAppt.id,
        doctorId: doctor.id,
        urgency: 'priority',
        reason: 'Recurrent migraine symptoms during exam periods',
        summary: 'Observed sleep deprivation and high stress markers',
        share: { summary: true, contact: false },
        consent: true,
      },
    });
    expect(referralRes.status()).toBe(201);
    const referral = (await referralRes.json()).referral;

    // 4. Doctor inspects referral: contact is hidden due to sharing preference
    const docViewRes = await request.get(`/api/referrals/${referral.id}`, { headers: authHeader(doctorToken) });
    expect(docViewRes.status()).toBe(200);
    const docView = (await docViewRes.json()).referral;
    expect(docView.summary).toBe('Observed sleep deprivation and high stress markers');
    expect(docView.contact).toBeNull();

    // 5. Doctor requests clarification & Counsellor replies
    const reqInfoRes = await request.post(`/api/referrals/${referral.id}/request-info`, {
      headers: authHeader(doctorToken),
      data: { items: ['Sleep pattern', 'Medication history'], message: 'Any reported sleep apnea?' },
    });
    expect(reqInfoRes.status()).toBe(200);

    const replyInfoRes = await request.post(`/api/referrals/${referral.id}/reply-info`, {
      headers: authHeader(counsellorToken),
      data: { index: 0, reply: 'Sleep duration erratic, approx 3-4 hours per night.' },
    });
    expect(replyInfoRes.status()).toBe(200);

    // 6. Doctor suggests slot and accepts referral
    const slotRes = await request.get(`/api/referrals/${referral.id}/suggest-slot`, { headers: authHeader(doctorToken) });
    expect(slotRes.status()).toBe(200);
    const slot = (await slotRes.json()).slot;

    const acceptRes = await request.post(`/api/referrals/${referral.id}/accept`, {
      headers: authHeader(doctorToken),
      data: { start: slot.start, mode: 'in_person' },
    });
    expect(acceptRes.status()).toBe(200);
    const consultationId = (await acceptRes.json()).consultationId;

    // 7. Doctor runs consultation
    await request.post(`/api/doctor/consultations/${consultationId}/start`, { headers: authHeader(doctorToken) });

    const updateConsultRes = await request.put(`/api/doctor/consultations/${consultationId}`, {
      headers: authHeader(doctorToken),
      data: {
        vitals: { bloodPressure: '120/80', avgSleep: '4 h' },
        assessment: 'Tension headache aggravated by sleep deficit',
        tags: ['Headache', 'Sleep'],
        clinicalNotes: 'Prescribed basic lifestyle adjustment; no neurological red flags detected.',
        plan: 'Follow-up in 2 weeks',
        shareSummary: true,
      },
    });
    expect(updateConsultRes.status()).toBe(200);

    const compRes = await request.post(`/api/doctor/consultations/${consultationId}/complete`, {
      headers: authHeader(doctorToken),
    });
    expect(compRes.status()).toBe(200);
    expect((await compRes.json()).consultation.status).toBe('completed');

    // 8. Security RBAC: Admin is forbidden from viewing private medical referral records
    const adminCheckRes = await request.get(`/api/referrals/${referral.id}`, { headers: authHeader(adminToken) });
    expect(adminCheckRes.status()).toBe(403);
  });
});
