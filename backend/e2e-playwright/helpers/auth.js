/**
 * Authentication helper for MindBridge Playwright API tests.
 */

const DEMO_ACCOUNTS = {
  student: 'it23714052@my.sliit.lk',
  counsellor: 'hasini.k@sliit.lk',
  doctor: 'ruwan.d@sliit.lk',
  admin: 'mindbrige.support@gmail.com',
};

async function loginUser(request, email, password = 'password123') {
  const loginRes = await request.post('/api/auth/login', {
    data: { email, password, device: 'Playwright Test Runner' },
  });

  const body = await loginRes.json();
  if (body.twoFactor) {
    const twoFactorRes = await request.post('/api/auth/login/2fa', {
      data: { email, code: body.devOtp, device: 'Playwright Test Runner' },
    });
    const twoFactorBody = await twoFactorRes.json();
    return twoFactorBody.token;
  }

  return body.token;
}

async function getRoleToken(request, role) {
  const email = DEMO_ACCOUNTS[role];
  if (!email) {
    throw new Error(`Unknown demo role: ${role}`);
  }
  return loginUser(request, email);
}

function authHeader(token) {
  return {
    Authorization: `Bearer ${token}`,
  };
}

module.exports = {
  DEMO_ACCOUNTS,
  loginUser,
  getRoleToken,
  authHeader,
};
