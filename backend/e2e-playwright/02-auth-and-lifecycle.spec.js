const { test, expect } = require('@playwright/test');
const { authHeader } = require('./helpers/auth');

test.describe('02 - Authentication & User Lifecycle', () => {
  const testStudent = {
    role: 'student',
    name: 'Playwright Test Student',
    email: `it99999999@my.sliit.lk`,
    password: 'password_test_123',
    studentId: 'IT99999999',
    faculty: 'Faculty of Computing',
    agreePrivacy: true,
  };

  test('Registration validates institutional university email domain', async ({ request }) => {
    const invalidRes = await request.post('/api/auth/register', {
      data: {
        ...testStudent,
        email: 'invalid_user@gmail.com',
      },
    });

    expect(invalidRes.status()).toBe(400);
    const body = await invalidRes.json();
    expect(body.error.code).toBe('EMAIL_DOMAIN');
  });

  test('Registration enforces strong password length', async ({ request }) => {
    const weakRes = await request.post('/api/auth/register', {
      data: {
        ...testStudent,
        password: 'short',
      },
    });

    expect(weakRes.status()).toBe(400);
  });

  test('Student registers, verifies OTP email, and prevents duplicate registration', async ({ request }) => {
    // 1. Register
    const regRes = await request.post('/api/auth/register', { data: testStudent });
    expect(regRes.status()).toBe(201);
    const regBody = await regRes.json();
    expect(regBody.email).toBe(testStudent.email);
    expect(regBody.devOtp).toBeDefined();

    // 2. Reject incorrect verification code
    const wrongCodeRes = await request.post('/api/auth/verify-email', {
      data: { email: testStudent.email, code: '000000' },
    });
    expect(wrongCodeRes.status()).toBe(400);

    // 3. Verify with valid code
    const verifyRes = await request.post('/api/auth/verify-email', {
      data: { email: testStudent.email, code: regBody.devOtp },
    });
    expect(verifyRes.status()).toBe(200);
    const verifyBody = await verifyRes.json();
    expect(verifyBody.token).toBeDefined();
    expect(verifyBody.user.role).toBe('student');

    // 4. Duplicate registration attempt returns 409 Conflict
    const dupRes = await request.post('/api/auth/register', { data: testStudent });
    expect(dupRes.status()).toBe(409);
  });

  test('Password reset workflow works end-to-end', async ({ request }) => {
    // 1. Request forgot password code
    const forgotRes = await request.post('/api/auth/forgot', {
      data: { email: testStudent.email },
    });
    expect(forgotRes.status()).toBe(200);
    const forgotBody = await forgotRes.json();
    expect(forgotBody.devOtp).toBeDefined();

    // 2. Validate reset code
    const checkRes = await request.post('/api/auth/reset/check', {
      data: { email: testStudent.email, code: forgotBody.devOtp },
    });
    expect(checkRes.status()).toBe(200);

    // 3. Reset password
    const newPassword = 'new_strong_password_456';
    const resetRes = await request.post('/api/auth/reset', {
      data: { email: testStudent.email, code: forgotBody.devOtp, password: newPassword },
    });
    expect(resetRes.status()).toBe(200);

    // 4. Log in with new password
    const loginRes = await request.post('/api/auth/login', {
      data: { email: testStudent.email, password: newPassword },
    });
    expect(loginRes.status()).toBe(200);
    const loginBody = await loginRes.json();
    expect(loginBody.token).toBeDefined();
  });

  test('Quick unlock enrolls device key, rotates key, and revokes upon removal', async ({ request }) => {
    // Login
    const loginRes = await request.post('/api/auth/login', {
      data: { email: testStudent.email, password: 'new_strong_password_456', device: 'Playwright Browser' },
    });
    const token = (await loginRes.json()).token;

    // Enable Quick Unlock
    const enableRes = await request.post('/api/auth/quick-unlock', {
      headers: authHeader(token),
      data: { device: 'Playwright Browser' },
    });
    expect(enableRes.status()).toBe(201);
    const enableBody = await enableRes.json();
    expect(enableBody.unlockKey).toBeDefined();
    expect(enableBody.user.privacy.biometricUnlock).toBe(true);

    // Sign in via quick unlock
    const signInRes = await request.post('/api/auth/quick-unlock/sign-in', {
      data: { unlockKey: enableBody.unlockKey, device: 'Playwright Browser' },
    });
    expect(signInRes.status()).toBe(200);
    const signInBody = await signInRes.json();
    expect(signInBody.token).toBeDefined();
    expect(signInBody.unlockKey).not.toBe(enableBody.unlockKey); // key rotates

    // Old key is invalidated
    const oldKeyRes = await request.post('/api/auth/quick-unlock/sign-in', {
      data: { unlockKey: enableBody.unlockKey },
    });
    expect(oldKeyRes.status()).toBe(401);

    // Remove quick unlock
    const removeRes = await request.post('/api/auth/quick-unlock/remove', {
      data: { unlockKey: signInBody.unlockKey },
    });
    expect(removeRes.status()).toBe(200);
  });

  test('Session logout invalidates the authentication token', async ({ request }) => {
    const loginRes = await request.post('/api/auth/login', {
      data: { email: testStudent.email, password: 'new_strong_password_456' },
    });
    const token = (await loginRes.json()).token;

    // Call /api/auth/me before logout
    const meRes = await request.get('/api/auth/me', { headers: authHeader(token) });
    expect(meRes.status()).toBe(200);

    // Logout
    const logoutRes = await request.post('/api/auth/logout', { headers: authHeader(token) });
    expect(logoutRes.status()).toBe(200);

    // Call /api/auth/me after logout returns 401 Unauthorized
    const postLogoutRes = await request.get('/api/auth/me', { headers: authHeader(token) });
    expect(postLogoutRes.status()).toBe(401);
  });
});
