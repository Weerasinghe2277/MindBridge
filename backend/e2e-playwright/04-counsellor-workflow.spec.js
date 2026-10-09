const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('04 - Counsellor Workflow & Session Management', () => {
  let counsellorToken;
  let studentToken;

  test.beforeAll(async ({ request }) => {
    counsellorToken = await getRoleToken(request, 'counsellor');
    studentToken = await getRoleToken(request, 'student');
  });

  test('Counsellor views pending requests, accepts appointment, and student receives confirmation', async ({ request }) => {
    const dashRes = await request.get('/api/staff/dashboard', { headers: authHeader(counsellorToken) });
    expect(dashRes.status()).toBe(200);
    const dash = await dashRes.json();
    expect(Array.isArray(dash.pending)).toBe(true);

    const pendingReq = dash.pending.find((a) => a.student.name === 'Pasindi Perera');
    if (pendingReq) {
      // 1. Accept appointment
      const acceptRes = await request.post(`/api/appointments/${pendingReq.id}/accept`, {
        headers: authHeader(counsellorToken),
      });
      expect(acceptRes.status()).toBe(200);
      const appt = (await acceptRes.json()).appointment;
      expect(appt.status).toBe('confirmed');
      expect(appt.meetingLink).toContain('https://meet.jit.si/');

      // 2. Student verifies status
      const studentViewRes = await request.get(`/api/appointments/${pendingReq.id}`, {
        headers: authHeader(studentToken),
      });
      expect(studentViewRes.status()).toBe(200);
      const studentView = (await studentViewRes.json()).appointment;
      expect(studentView.statusLabel).toBe('Confirmed');
    }
  });

  test('Counsellor session execution, confidential notes, and completion', async ({ request }) => {
    // Find a confirmed appointment
    const upcomingRes = await request.get('/api/appointments?scope=upcoming', {
      headers: authHeader(counsellorToken),
    });
    expect(upcomingRes.status()).toBe(200);
    const confirmedAppt = (await upcomingRes.json()).appointments.find((a) => a.status === 'confirmed');

    if (confirmedAppt) {
      // 1. Start session
      const startRes = await request.post(`/api/appointments/${confirmedAppt.id}/session/start`, {
        headers: authHeader(counsellorToken),
      });
      expect(startRes.status()).toBe(200);

      // 2. Save clinical notes
      const notesRes = await request.put(`/api/appointments/${confirmedAppt.id}/notes`, {
        headers: authHeader(counsellorToken),
        data: {
          summary: 'Student experiencing academic fatigue and sleep disturbance.',
          plan: 'Introduce progressive muscle relaxation and sleep hygiene guidelines.',
          tags: ['Sleep', 'Anxiety'],
          goals: [{ text: 'Target 7 hours sleep per night', done: false }],
          recommendReferral: false,
        },
      });
      expect(notesRes.status()).toBe(200);

      // 3. Counsellor can read the notes
      const readNotesRes = await request.get(`/api/appointments/${confirmedAppt.id}/notes`, {
        headers: authHeader(counsellorToken),
      });
      expect(readNotesRes.status()).toBe(200);
      const noteBody = await readNotesRes.json();
      expect(noteBody.note.summary).toContain('academic fatigue');

      // 4. Confidentiality check: Student is forbidden from accessing clinical notes
      const studentNoteRes = await request.get(`/api/appointments/${confirmedAppt.id}/notes`, {
        headers: authHeader(studentToken),
      });
      expect(studentNoteRes.status()).toBe(403);

      // 5. Complete session
      const completeRes = await request.post(`/api/appointments/${confirmedAppt.id}/complete`, {
        headers: authHeader(counsellorToken),
        data: { noShow: false },
      });
      expect(completeRes.status()).toBe(200);
      expect((await completeRes.json()).appointment.status).toBe('completed');
    }
  });

  test('Counsellor availability configuration and block conflict detection', async ({ request }) => {
    // 1. Get weekly availability
    const avRes = await request.get('/api/staff/availability', { headers: authHeader(counsellorToken) });
    expect(avRes.status()).toBe(200);
    const av = await avRes.json();
    expect(av.week.length).toBe(7);

    // 2. Update buffer and session length
    const updateRes = await request.put('/api/staff/availability', {
      headers: authHeader(counsellorToken),
      data: { sessionLength: 45, bufferMinutes: 15 },
    });
    expect(updateRes.status()).toBe(200);

    // 3. Invalid working hours rejected (start after end)
    const invalidHoursRes = await request.put('/api/staff/availability', {
      headers: authHeader(counsellorToken),
      data: { startTime: '17:00', endTime: '09:00' },
    });
    expect(invalidHoursRes.status()).toBe(400);

    // Restore standard 30 min length
    await request.put('/api/staff/availability', {
      headers: authHeader(counsellorToken),
      data: { sessionLength: 30, bufferMinutes: 0 },
    });
  });
});
