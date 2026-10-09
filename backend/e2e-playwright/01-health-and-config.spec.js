const { test, expect } = require('@playwright/test');

test.describe('01 - System Health & Public Configuration', () => {
  test('GET /api/health returns healthy status and active database connection', async ({ request }) => {
    const res = await request.get('/api/health');
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.db).toBe(true);
    expect(body).toHaveProperty('time');
  });

  test('GET /api/config returns public configuration with national mental health helpline', async ({ request }) => {
    const res = await request.get('/api/config');
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(body.helpline).toBe('1926');
    expect(body).toHaveProperty('autoSignOutMinutes');
    expect(typeof body.showHelplineEverywhere).toBe('boolean');
  });
});
