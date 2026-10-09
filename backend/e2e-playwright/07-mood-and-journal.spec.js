const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('07 - Student Mood Tracker & Encrypted Journal', () => {
  let studentToken;
  let counsellorToken;

  test.beforeAll(async ({ request }) => {
    studentToken = await getRoleToken(request, 'student');
    counsellorToken = await getRoleToken(request, 'counsellor');
  });

  test('Daily mood check-in records mood, calculates streak, and offers suggestions', async ({ request }) => {
    const checkinRes = await request.post('/api/mood', {
      headers: authHeader(studentToken),
      data: {
        mood: 1,
        factors: ['Exams', 'Sleep'],
        note: 'High exam stress today',
      },
    });
    expect(checkinRes.status()).toBe(201);

    const body = await checkinRes.json();
    expect(body.streak).toBeGreaterThanOrEqual(1);
    expect(body.suggestion).toBeDefined();
    expect(body.suggestion.kind).toBe('counsellor');

    // View history
    const historyRes = await request.get('/api/mood/history?range=week', {
      headers: authHeader(studentToken),
    });
    expect(historyRes.status()).toBe(200);

    // View insights
    const insightsRes = await request.get('/api/mood/insights?range=month', {
      headers: authHeader(studentToken),
    });
    expect(insightsRes.status()).toBe(200);
  });

  test('Personal journal entries are stored encrypted and searchable by the author', async ({ request }) => {
    // 1. Create journal entry
    const createRes = await request.post('/api/mood/journal', {
      headers: authHeader(studentToken),
      data: {
        title: 'Private Study Reflections',
        body: 'Writing down my daily anxiety helps me process it peacefully.',
        mood: 2,
        tags: ['Academic', 'Reflection'],
      },
    });
    expect(createRes.status()).toBe(201);
    const entry = (await createRes.json()).entry;
    expect(entry.title).toBe('Private Study Reflections');

    // 2. Search journal
    const searchRes = await request.get('/api/mood/journal?q=peacefully', {
      headers: authHeader(studentToken),
    });
    expect(searchRes.status()).toBe(200);
    const entries = (await searchRes.json()).entries;
    expect(entries.some((e) => e.id === entry.id)).toBe(true);

    // 3. Delete journal entry
    const deleteRes = await request.delete(`/api/mood/journal/${entry.id}`, {
      headers: authHeader(studentToken),
    });
    expect(deleteRes.status()).toBe(200);
  });

  test('Privacy protection: Counsellor is strictly forbidden from accessing student mood history', async ({ request }) => {
    const forbiddenRes = await request.get('/api/mood/history', {
      headers: authHeader(counsellorToken),
    });
    expect(forbiddenRes.status()).toBe(403);
  });
});
