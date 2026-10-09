const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('03 - Student Counselling & Appointment Booking', () => {
  let studentToken;

  test.beforeAll(async ({ request }) => {
    studentToken = await getRoleToken(request, 'student');
  });

  test('Student retrieves list of qualified counsellors', async ({ request }) => {
    const res = await request.get('/api/counsellors', {
      headers: authHeader(studentToken),
    });
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(Array.isArray(body.counsellors)).toBe(true);
    expect(body.counsellors.length).toBeGreaterThanOrEqual(1);

    const first = body.counsellors[0];
    expect(first).toHaveProperty('id');
    expect(first).toHaveProperty('name');
    expect(first).toHaveProperty('focusAreas');
  });

  test('Student views slot availability and books an appointment', async ({ request }) => {
    // 1. Get counsellors list
    const listRes = await request.get('/api/counsellors', {
      headers: authHeader(studentToken),
    });
    const counsellors = (await listRes.json()).counsellors;
    const counsellorWithSlots = counsellors.find((c) => c.next);
    expect(counsellorWithSlots).toBeDefined();

    // 2. Book appointment
    const regRes = await request.post('/api/auth/register', {
      data: {
        role: 'student',
        name: 'Booking Student',
        email: 'it88888888@my.sliit.lk',
        password: 'password123',
        studentId: 'IT88888888',
        faculty: 'Faculty of Computing',
        agreePrivacy: true,
      },
    });
    const regBody = await regRes.json();
    const verifyRes = await request.post('/api/auth/verify-email', {
      data: { email: regBody.email, code: regBody.devOtp },
    });
    const freshToken = (await verifyRes.json()).token;

    const bookRes = await request.post('/api/appointments', {
      headers: authHeader(freshToken),
      data: {
        counsellorId: counsellorWithSlots.id,
        start: counsellorWithSlots.next.start,
        mode: counsellorWithSlots.modes[0],
        note: 'Preparation for upcoming final exams',
      },
    });
    expect(bookRes.status()).toBe(201);
    const bookBody = await bookRes.json();
    expect(bookBody.appointment.status).toBe('pending');
    expect(bookBody.appointment.timeline.length).toBe(4);

    // 3. Duplicate booking attempt while one is active returns 409
    const dupRes = await request.post('/api/appointments', {
      headers: authHeader(freshToken),
      data: {
        counsellorId: counsellorWithSlots.id,
        start: counsellorWithSlots.next.start,
        mode: counsellorWithSlots.modes[0],
      },
    });
    expect(dupRes.status()).toBe(409);
    expect((await dupRes.json()).error.code).toBe('DUPLICATE_BOOKING');

    // 4. Student cancels their pending appointment
    const cancelRes = await request.post(`/api/appointments/${bookBody.appointment.id}/cancel`, {
      headers: authHeader(freshToken),
      data: { reason: 'Schedule conflict with lecture' },
    });
    expect(cancelRes.status()).toBe(200);

    const checkRes = await request.get(`/api/appointments/${bookBody.appointment.id}`, {
      headers: authHeader(freshToken),
    });
    expect((await checkRes.json()).appointment.status).toBe('cancelled');
  });

  test('Anonymous booking constraints: in-person is rejected, online hides identity from counsellor', async ({ request }) => {
    // Fresh student
    const regRes = await request.post('/api/auth/register', {
      data: {
        role: 'student',
        name: 'Anon Student',
        email: 'it77777777@my.sliit.lk',
        password: 'password123',
        studentId: 'IT77777777',
        faculty: 'Faculty of Computing',
        agreePrivacy: true,
      },
    });
    const regBody = await regRes.json();
    const verifyRes = await request.post('/api/auth/verify-email', {
      data: { email: regBody.email, code: regBody.devOtp },
    });
    const anonStudentToken = (await verifyRes.json()).token;

    const listRes = await request.get('/api/counsellors', { headers: authHeader(anonStudentToken) });
    const hasini = (await listRes.json()).counsellors.find((c) => c.name.includes('Hasini'));
    expect(hasini).toBeDefined();

    // 1. In-person anonymous booking is rejected (must be online)
    const inPersonRes = await request.post('/api/appointments', {
      headers: authHeader(anonStudentToken),
      data: {
        counsellorId: hasini.id,
        start: hasini.next.start,
        mode: 'in_person',
        anonymous: true,
      },
    });
    expect(inPersonRes.status()).toBe(400);

    // 2. Online anonymous booking succeeds
    const onlineRes = await request.post('/api/appointments', {
      headers: authHeader(anonStudentToken),
      data: {
        counsellorId: hasini.id,
        start: hasini.next.start,
        mode: 'online',
        anonymous: true,
        note: 'Feeling overwhelmed',
      },
    });
    expect(onlineRes.status()).toBe(201);
    const appointmentId = (await onlineRes.json()).appointment.id;

    // 3. Counsellor views appointment: student identity is anonymized
    const counsellorToken = await getRoleToken(request, 'counsellor');
    const counsellorViewRes = await request.get(`/api/appointments/${appointmentId}`, {
      headers: authHeader(counsellorToken),
    });
    expect(counsellorViewRes.status()).toBe(200);
    const counsellorView = (await counsellorViewRes.json()).appointment;
    expect(counsellorView.student.name).toBe('Anonymous student');
    expect(counsellorView.student.id).toBeNull();
  });
});
