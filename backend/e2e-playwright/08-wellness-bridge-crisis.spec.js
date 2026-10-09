const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('08 - Bridge AI Assistant & Crisis Escalation Protocol', () => {
  let studentToken;

  test.beforeAll(async ({ request }) => {
    studentToken = await getRoleToken(request, 'student');
  });

  test('Bridge provides supportive advice for standard queries without crisis escalation', async ({ request }) => {
    const res = await request.post('/api/wellness/bridge', {
      headers: authHeader(studentToken),
      data: { text: 'I am preparing for examinations and feeling a bit nervous.' },
    });
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.escalate).toBe(false);
    expect(body.reply).toBeDefined();
    expect(body.reply.text).toBeDefined();
  });

  test('Bridge automatically escalates suicidal/self-harm messages to the 1926 helpline', async ({ request }) => {
    const crisisMessages = [
      'I don’t want to live anymore',
      "I can't go on",
      'thinking about self-harm',
      'I want to end my life',
    ];

    for (const msg of crisisMessages) {
      const res = await request.post('/api/wellness/bridge', {
        headers: authHeader(studentToken),
        data: { text: msg },
      });
      expect(res.status()).toBe(201);
      const body = await res.json();
      expect(body.escalate).toBe(true);
      expect(body.reply.text).toContain('1926');
    }
  });

  test('Helpline tap event tracking and conversation reset', async ({ request }) => {
    // 1. Record emergency tap
    const tapRes = await request.post('/api/wellness/events', {
      headers: authHeader(studentToken),
      data: { kind: 'helpline_tap', detail: '1926' },
    });
    expect(tapRes.status()).toBe(201);

    // 2. Clear Bridge conversation history
    const deleteRes = await request.delete('/api/wellness/bridge', {
      headers: authHeader(studentToken),
    });
    expect(deleteRes.status()).toBe(200);
  });
});
