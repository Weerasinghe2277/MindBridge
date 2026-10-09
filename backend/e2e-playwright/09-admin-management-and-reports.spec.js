const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('09 - Admin Administration, Verifications & Anonymised Reporting', () => {
  let adminToken;
  let studentToken;

  test.beforeAll(async ({ request }) => {
    adminToken = await getRoleToken(request, 'admin');
    studentToken = await getRoleToken(request, 'student');
  });

  test('Admin reviews pending staff verifications and downloads single-use verification documents', async ({ request }) => {
    const appsRes = await request.get('/api/admin/verifications?role=counsellor&status=pending', {
      headers: authHeader(adminToken),
    });
    expect(appsRes.status()).toBe(200);
    const apps = (await appsRes.json()).applications;
    expect(apps.length).toBeGreaterThanOrEqual(1);

    const app = apps[0];
    const detailRes = await request.get(`/api/admin/verifications/${app.id}`, {
      headers: authHeader(adminToken),
    });
    expect(detailRes.status()).toBe(200);
    const detail = (await detailRes.json()).application;

    if (detail.verification && detail.verification.documents && detail.verification.documents.length) {
      const doc = detail.verification.documents[0];

      // Mark document checked
      const checkDocRes = await request.patch(`/api/admin/verifications/${app.id}/documents/${doc.id}`, {
        headers: authHeader(adminToken),
        data: { checked: true },
      });
      expect(checkDocRes.status()).toBe(200);

      // Generate single-use secure download link
      const downloadLinkRes = await request.post('/api/download', {
        headers: authHeader(adminToken),
        data: { target: 'document', ownerId: app.id, docId: doc.id },
      });
      expect(downloadLinkRes.status()).toBe(201);
      const downloadPath = (await downloadLinkRes.json()).path;

      // 1st download succeeds (PDF)
      const fetchFileRes = await request.get(downloadPath);
      expect(fetchFileRes.status()).toBe(200);
      expect(fetchFileRes.headers()['content-type']).toBe('application/pdf');

      // 2nd download fails: links are single-use
      const fetchAgainRes = await request.get(downloadPath);
      expect(fetchAgainRes.status()).toBe(404);
    }
  });

  test('Admin user management: search, role transition, and status deactivation validation', async ({ request }) => {
    // 1. Search student users
    const usersRes = await request.get('/api/admin/users?role=student&q=nimal', {
      headers: authHeader(adminToken),
    });
    expect(usersRes.status()).toBe(200);
    const users = (await usersRes.json()).users;
    expect(users.length).toBeGreaterThanOrEqual(1);
    const targetUser = users[0];

    // 2. Change role
    const roleRes = await request.patch(`/api/admin/users/${targetUser.id}/role`, {
      headers: authHeader(adminToken),
      data: { role: 'admin' },
    });
    expect(roleRes.status()).toBe(200);
    expect((await roleRes.json()).to).toBe('Admin');

    // 3. Deactivate status requires mandatory reason (400 if reason missing)
    const missingReasonRes = await request.patch(`/api/admin/users/${targetUser.id}/status`, {
      headers: authHeader(adminToken),
      data: { status: 'deactivated' },
    });
    expect(missingReasonRes.status()).toBe(400);

    // 4. Deactivate with reason succeeds
    const deactRes = await request.patch(`/api/admin/users/${targetUser.id}/status`, {
      headers: authHeader(adminToken),
      data: { status: 'deactivated', reason: 'Audit flagged inactive profile' },
    });
    expect(deactRes.status()).toBe(200);
  });

  test('Admin system settings enforce privacy thresholds and audit logging', async ({ request }) => {
    // 1. Update appointment window
    const windowRes = await request.patch('/api/admin/settings/appointments', {
      headers: authHeader(adminToken),
      data: { bookingWindowDays: 14 },
    });
    expect(windowRes.status()).toBe(200);

    // 2. Privacy floor cannot be lowered below minimum (policy protection)
    await request.patch('/api/admin/settings/privacy', {
      headers: authHeader(adminToken),
      data: { minReportGroupSize: 1 },
    });
    const cfgRes = await request.get('/api/admin/settings', { headers: authHeader(adminToken) });
    expect((await cfgRes.json()).settings.privacy.minReportGroupSize).toBe(10);

    // 3. Audit logs retrieval
    const logsRes = await request.get('/api/admin/logs?category=verification', {
      headers: authHeader(adminToken),
    });
    expect(logsRes.status()).toBe(200);
    expect((await logsRes.json()).logs.length).toBeGreaterThanOrEqual(1);
  });

  test('Anonymised reports generation and CSV export', async ({ request }) => {
    // Overview report
    const overviewRes = await request.get('/api/admin/reports/overview?range=semester', {
      headers: authHeader(adminToken),
    });
    expect(overviewRes.status()).toBe(200);
    expect((await overviewRes.json()).minGroup).toBe(10);

    // Specific category reports
    for (const reportType of ['appointments', 'types', 'usage', 'wellness', 'users']) {
      const repRes = await request.get(`/api/admin/reports/${reportType}?range=semester`, {
        headers: authHeader(adminToken),
      });
      expect(repRes.status()).toBe(200);
    }

    // Export CSV report
    const csvLinkRes = await request.post('/api/download', {
      headers: authHeader(adminToken),
      data: { target: 'report', query: { range: 'semester', format: 'csv', sections: 'appointments,usage' } },
    });
    expect(csvLinkRes.status()).toBe(201);
    const csvPath = (await csvLinkRes.json()).path;

    const fileRes = await request.get(csvPath);
    expect(fileRes.status()).toBe(200);
    const text = await fileRes.text();
    expect(text).toMatch(/^Section,Metric,Value/);
  });

  test('Non-admin users are strictly forbidden from administrative endpoints (RBAC)', async ({ request }) => {
    const forbiddenRes = await request.get('/api/admin/users', {
      headers: authHeader(studentToken),
    });
    expect(forbiddenRes.status()).toBe(403);
  });
});
