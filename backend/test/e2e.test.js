// End-to-end API tests for every role's main flows, run against an isolated
// in-memory MongoDB with the demo seed.   npm test
process.env.USE_MEMORY_DB = 'true';
process.env.NODE_ENV = 'test';
process.env.CLOUDINARY_URL = ''; // always test against GridFS, never a real Cloudinary account

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { connectDb, disconnectDb } = require('../src/config/db');
const { seed } = require('../src/seed/seed');
const app = require('../src/app');
const T = require('../src/utils/time');

let server;
let base;
const tokens = {};

async function call(method, path, token, body) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: res.status, body: json, headers: res.headers };
}
const ok = (r, status = 200) => {
  assert.equal(r.status, status, JSON.stringify(r.body).slice(0, 300));
  return r.body;
};

async function login(email) {
  let r = ok(await call('POST', '/auth/login', null, { email, password: 'password123', device: 'test' }));
  if (r.twoFactor) r = ok(await call('POST', '/auth/login/2fa', null, { email, code: r.devOtp, device: 'test' }));
  return r.token;
}

before(async () => {
  await connectDb();
  await seed({ quiet: true });
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}/api`;
  tokens.student = await login('it23714052@my.sliit.lk');
  tokens.counsellor = await login('hasini.k@sliit.lk');
  tokens.doctor = await login('ruwan.d@sliit.lk');
  tokens.admin = await login('mindbrige.support@gmail.com');
});

after(async () => {
  server.close();
  await disconnectDb();
});

test('registration, email verification and validation', async () => {
  const bad = await call('POST', '/auth/register', null, { role: 'student', name: 'A B', email: 'a@gmail.com', password: 'abcdefg1', studentId: 'IT11111111', faculty: 'Faculty of Computing', agreePrivacy: true });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error.code, 'EMAIL_DOMAIN');
  const weak = await call('POST', '/auth/register', null, { role: 'student', name: 'A B', email: 'it11111111@my.sliit.lk', password: 'short', studentId: 'IT11111111', faculty: 'Faculty of Computing', agreePrivacy: true });
  assert.equal(weak.status, 400);
  const r = ok(await call('POST', '/auth/register', null, { role: 'student', name: 'New Student', email: 'it11111111@my.sliit.lk', password: 'abcdefg1', studentId: 'IT11111111', faculty: 'Faculty of Computing', agreePrivacy: true }), 201);
  const wrong = await call('POST', '/auth/verify-email', null, { email: r.email, code: '000000' });
  assert.equal(wrong.status, 400);
  const v = ok(await call('POST', '/auth/verify-email', null, { email: r.email, code: r.devOtp }));
  assert.ok(v.token);
  assert.equal(v.user.role, 'student');
  const dup = await call('POST', '/auth/register', null, { role: 'student', name: 'Another Person', email: 'it11111111@my.sliit.lk', password: 'abcdefg1', studentId: 'IT11111112', faculty: 'Faculty of Computing', agreePrivacy: true });
  assert.equal(dup.status, 409);
});

test('password reset flow', async () => {
  const f = ok(await call('POST', '/auth/forgot', null, { email: 'it11111111@my.sliit.lk' }));
  ok(await call('POST', '/auth/reset/check', null, { email: 'it11111111@my.sliit.lk', code: f.devOtp }));
  ok(await call('POST', '/auth/reset', null, { email: 'it11111111@my.sliit.lk', code: f.devOtp, password: 'newpass99' }));
  const r = ok(await call('POST', '/auth/login', null, { email: 'it11111111@my.sliit.lk', password: 'newpass99' }));
  assert.ok(r.token);
});

test('quick unlock: device key signs in, rotates, and is revoked by password reset', async () => {
  const email = 'it11111111@my.sliit.lk';
  const t = ok(await call('POST', '/auth/login', null, { email, password: 'newpass99', device: 'Pixel test' })).token;
  const on = ok(await call('POST', '/auth/quick-unlock', t, { device: 'Pixel test' }), 201);
  assert.ok(on.unlockKey.length >= 40);
  assert.equal(on.user.privacy.biometricUnlock, true);

  const s1 = ok(await call('POST', '/auth/quick-unlock/sign-in', null, { unlockKey: on.unlockKey, device: 'Pixel test' }));
  assert.ok(s1.token);
  assert.equal(s1.user.email, email);
  assert.notEqual(s1.unlockKey, on.unlockKey);
  ok(await call('GET', '/auth/me', s1.token));
  // The old key was replaced, so a copy of it no longer works.
  const reused = await call('POST', '/auth/quick-unlock/sign-in', null, { unlockKey: on.unlockKey });
  assert.equal(reused.status, 401);
  assert.equal(reused.body.error.code, 'QUICK_UNLOCK_INVALID');

  // Turning it off on the phone removes the key.
  ok(await call('POST', '/auth/quick-unlock/remove', null, { unlockKey: s1.unlockKey }));
  assert.equal((await call('POST', '/auth/quick-unlock/sign-in', null, { unlockKey: s1.unlockKey })).status, 401);
  assert.equal(ok(await call('GET', '/auth/me', s1.token)).user.privacy.biometricUnlock, false);

  // A password reset turns quick unlock off everywhere.
  const again = ok(await call('POST', '/auth/quick-unlock', s1.token, {}), 201);
  const f = ok(await call('POST', '/auth/forgot', null, { email }));
  ok(await call('POST', '/auth/reset', null, { email, code: f.devOtp, password: 'newpass99' }));
  assert.equal((await call('POST', '/auth/quick-unlock/sign-in', null, { unlockKey: again.unlockKey })).status, 401);
});

test('student booking: duplicate block, slot race and new booking (FR2, FR3, FR7)', async () => {
  const fresh = (await call('POST', '/auth/login', null, { email: 'it11111111@my.sliit.lk', password: 'newpass99' })).body.token;
  const list = ok(await call('GET', '/counsellors', fresh)).counsellors;
  assert.ok(list.length >= 4);
  const c = list.find((x) => x.next);
  const booked = ok(await call('POST', '/appointments', fresh, { counsellorId: c.id, start: c.next.start, mode: c.modes[0], note: 'Exam stress' }), 201).appointment;
  assert.equal(booked.status, 'pending');
  assert.equal(booked.timeline.length, 4);
  // A second booking is blocked while one is active (FR7).
  const second = await call('POST', '/appointments', fresh, { counsellorId: c.id, start: c.next.start, mode: c.modes[0] });
  assert.equal(second.status, 409);
  assert.equal(second.body.error.code, 'DUPLICATE_BOOKING');
  // Another student can't take the same slot.
  const other = await login('it22510933@my.sliit.lk'); // Kasun
  const taken = await call('POST', '/appointments', tokens.student, { counsellorId: c.id, start: c.next.start, mode: c.modes[0] });
  assert.equal(taken.status, 409);
  assert.ok(other);
  // Student cancels (pending: allowed any time).
  ok(await call('POST', `/appointments/${booked.id}/cancel`, fresh, { reason: 'Changed my mind' }));
  const again = ok(await call('GET', `/appointments/${booked.id}`, fresh)).appointment;
  assert.equal(again.status, 'cancelled');
});

test('counsellor: accept, propose, student accepts proposal, session and notes (FR6, NFR5)', async () => {
  const dash = ok(await call('GET', '/staff/dashboard', tokens.counsellor));
  const req = dash.pending.find((a) => a.student.name === 'Pasindi Perera');
  assert.ok(req, 'Pasindi has a pending request');
  const acc = ok(await call('POST', `/appointments/${req.id}/accept`, tokens.counsellor)).appointment;
  assert.equal(acc.status, 'confirmed');
  assert.ok(acc.meetingLink.startsWith('https://meet.jit.si/'));
  // The student sees the same status (NFR5).
  const seen = ok(await call('GET', `/appointments/${req.id}`, tokens.student)).appointment;
  assert.equal(seen.statusLabel, 'Confirmed');

  const me = ok(await call('GET', '/auth/me', tokens.counsellor)).user;
  const date = T.addDays(T.todayStr(), 9);
  let slots = [];
  for (let i = 0; i < 10 && !slots.length; i++) {
    slots = ok(await call('GET', `/counsellors/${me.id}/slots?date=${T.addDays(date, i)}&exclude=${req.id}`, tokens.counsellor)).slots.filter((s) => s.available);
  }
  const prop = ok(await call('POST', `/appointments/${req.id}/reschedule`, tokens.counsellor, { start: slots[0].start, reason: 'Clinic meeting' })).appointment;
  assert.equal(prop.status, 'reschedule_proposed');
  const moved = ok(await call('POST', `/appointments/${req.id}/proposal`, tokens.student, { accept: true })).appointment;
  assert.equal(moved.status, 'confirmed');
  assert.equal(new Date(moved.start).toISOString(), slots[0].start);

  ok(await call('POST', `/appointments/${req.id}/session/start`, tokens.counsellor));
  ok(await call('PUT', `/appointments/${req.id}/notes`, tokens.counsellor, { summary: 'Discussed sleep', plan: 'Box breathing', tags: ['Sleep'], goals: [{ text: 'Sleep by 11', done: false }], recommendReferral: true }));
  const notes = ok(await call('GET', `/appointments/${req.id}/notes`, tokens.counsellor)).note;
  assert.equal(notes.summary, 'Discussed sleep');
  const done = ok(await call('POST', `/appointments/${req.id}/complete`, tokens.counsellor, { noShow: false }));
  assert.equal(done.appointment.status, 'completed');
  // Students can't read session notes.
  const blocked = await call('GET', `/appointments/${req.id}/notes`, tokens.student);
  assert.equal(blocked.status, 403);
});

test('counsellor: decline with suggestions, duplicates view and cancel', async () => {
  const reqs = ok(await call('GET', '/appointments?scope=requests', tokens.counsellor)).appointments;
  const kasun = reqs.find((a) => a.duplicateFlag);
  assert.ok(kasun, 'seeded duplicate request');
  const dup = ok(await call('GET', `/appointments/${kasun.id}/duplicates`, tokens.counsellor));
  assert.ok(dup.others.length >= 1);
  ok(await call('POST', `/appointments/${kasun.id}/ask-student`, tokens.counsellor));
  const dec = ok(await call('POST', `/appointments/${kasun.id}/decline`, tokens.counsellor, { reason: 'Time is no longer available', message: 'Try Friday', suggestSlots: true })).appointment;
  assert.equal(dec.status, 'declined');
  assert.equal(dec.decline.suggestedSlots.length, 3);
  const upcoming = ok(await call('GET', '/appointments?scope=upcoming', tokens.counsellor)).appointments.filter((a) => a.status === 'confirmed');
  const noReason = await call('POST', `/appointments/${upcoming[0].id}/cancel`, tokens.counsellor, {});
  assert.equal(noReason.status, 400);
  ok(await call('POST', `/appointments/${upcoming[0].id}/cancel`, tokens.counsellor, { reason: 'Unwell today' }));
});

test('availability: hours, blocks and booking conflicts (FR2)', async () => {
  const av = ok(await call('GET', '/staff/availability', tokens.counsellor));
  assert.equal(av.week.length, 7);
  ok(await call('PUT', '/staff/availability', tokens.counsellor, { sessionLength: 45, bufferMinutes: 15 }));
  const bad = await call('PUT', '/staff/availability', tokens.counsellor, { startTime: '17:00', endTime: '09:00' });
  assert.equal(bad.status, 400);
  ok(await call('PUT', '/staff/availability', tokens.counsellor, { sessionLength: 30, bufferMinutes: 0 }));
  const appts = ok(await call('GET', '/appointments?scope=upcoming', tokens.counsellor)).appointments.filter((a) => a.status === 'confirmed');
  // A 30-minute block must end by 23:59, so skip late-evening bookings (seed times follow the clock).
  const a = appts.find((x) => T.toMinutes(T.local(x.start).time) + 30 < 24 * 60);
  const d = T.local(a.start);
  const clash = await call('POST', '/staff/availability/blocks', tokens.counsellor, { date: d.dateStr, from: d.time, to: T.fromMinutes(T.toMinutes(d.time) + 30), reason: 'Meeting' });
  assert.equal(clash.status, 409);
  assert.equal(clash.body.error.code, 'BLOCK_CONFLICT');
  const forced = ok(await call('POST', '/staff/availability/blocks', tokens.counsellor, { date: d.dateStr, from: d.time, to: T.fromMinutes(T.toMinutes(d.time) + 30), reason: 'Meeting', force: true }), 201);
  const block = forced.availability.blocks.find((b) => b.date === d.dateStr && b.from === d.time);
  ok(await call('DELETE', `/staff/availability/blocks/${block.id}`, tokens.counsellor));
});

test('referral to doctor, information request and consultation (NFR1, NFR2)', async () => {
  const past = ok(await call('GET', '/appointments?scope=past', tokens.counsellor)).appointments.find((a) => a.status === 'completed' && a.student.name !== 'Pasindi Perera');
  const docs = ok(await call('GET', '/staff/doctors', tokens.counsellor)).doctors;
  const noConsent = await call('POST', '/referrals', tokens.counsellor, { appointmentId: past.id, doctorId: docs[0].id, urgency: 'routine', reason: 'Recurring headaches for a month', share: { summary: true, contact: false }, consent: false });
  assert.equal(noConsent.status, 400);
  const ref = ok(await call('POST', '/referrals', tokens.counsellor, { appointmentId: past.id, doctorId: docs[0].id, urgency: 'priority', reason: 'Recurring headaches for a month', summary: 'Two sessions', share: { summary: true, contact: false }, consent: true }), 201).referral;
  // The doctor only sees what was shared.
  const seen = ok(await call('GET', `/referrals/${ref.id}`, tokens.doctor)).referral;
  assert.equal(seen.contact, null);
  assert.equal(seen.summary, 'Two sessions');
  ok(await call('POST', `/referrals/${ref.id}/request-info`, tokens.doctor, { items: ['Sleep pattern'], message: 'Typical sleep times?' }));
  ok(await call('POST', `/referrals/${ref.id}/reply-info`, tokens.counsellor, { index: 0, reply: 'Sleeps 2am to 7am' }));
  const slot = ok(await call('GET', `/referrals/${ref.id}/suggest-slot`, tokens.doctor)).slot;
  const acc = ok(await call('POST', `/referrals/${ref.id}/accept`, tokens.doctor, { start: slot.start, mode: 'in_person' }));
  const cid = acc.consultationId;
  ok(await call('POST', `/doctor/consultations/${cid}/start`, tokens.doctor));
  ok(await call('PUT', `/doctor/consultations/${cid}`, tokens.doctor, { vitals: { bloodPressure: '120/80', avgSleep: '5 h' }, assessment: 'Tension headache', tags: ['Headache'], clinicalNotes: 'No red flags', plan: 'Hydration, review in 2 weeks', shareSummary: true }));
  const full = ok(await call('GET', `/doctor/consultations/${cid}`, tokens.doctor)).consultation;
  assert.equal(full.clinicalNotes, 'No red flags');
  const comp = ok(await call('POST', `/doctor/consultations/${cid}/complete`, tokens.doctor));
  assert.equal(comp.consultation.status, 'completed');
  const day = T.addDays(T.todayStr(), 14);
  let fu = [];
  for (let i = 0; i < 7 && !fu.length; i++) fu = ok(await call('GET', `/doctor/slots?date=${T.addDays(day, i)}`, tokens.doctor)).slots.filter((s) => s.available);
  ok(await call('POST', `/doctor/consultations/${cid}/follow-up`, tokens.doctor, { start: fu[0].start, mode: 'online', notifyCounsellor: true }), 201);
  // Admins can't open referrals.
  assert.equal((await call('GET', `/referrals/${ref.id}`, tokens.admin)).status, 403);
});

test('articles: write, submit, moderate, revise live article', async () => {
  const short = await call('POST', '/articles', tokens.counsellor, { title: 'Hi', category: 'Stress', body: 'Too short' });
  assert.equal(short.status, 400);
  const a = ok(await call('POST', '/articles', tokens.counsellor, { title: 'Study breaks that work', category: 'Academic', body: 'Taking a five minute break every fifty minutes helps you stay focused and remember more of what you read.' }), 201).article;
  ok(await call('POST', `/articles/${a.id}/submit`, tokens.counsellor));
  ok(await call('POST', `/admin/articles/${a.id}/reject`, tokens.admin, { reason: 'Tone not suitable', feedback: 'Add a support link' }));
  ok(await call('PUT', `/articles/${a.id}`, tokens.counsellor, { title: 'Study breaks that work', category: 'Academic', body: 'Taking a five minute break every fifty minutes helps you stay focused. If stress builds, book a counsellor.' }));
  ok(await call('POST', `/articles/${a.id}/submit`, tokens.counsellor));
  ok(await call('POST', `/admin/articles/${a.id}/approve`, tokens.admin));
  const pub = ok(await call('GET', `/articles/${a.id}`, tokens.student)).article;
  assert.equal(pub.status, 'published');
  // Edit to a live article waits for review; students still see the old text.
  ok(await call('PUT', `/articles/${a.id}`, tokens.counsellor, { title: 'Study breaks that really work', category: 'Academic', body: 'Updated text that is long enough to pass validation for the article body field.' }));
  ok(await call('POST', `/articles/${a.id}/submit`, tokens.counsellor));
  assert.equal(ok(await call('GET', `/articles/${a.id}`, tokens.student)).article.title, 'Study breaks that work');
  ok(await call('POST', `/admin/articles/${a.id}/approve`, tokens.admin));
  assert.equal(ok(await call('GET', `/articles/${a.id}`, tokens.student)).article.title, 'Study breaks that really work');
  ok(await call('POST', `/articles/${a.id}/save`, tokens.student));
  assert.ok(ok(await call('GET', '/articles/saved', tokens.student)).articles.some((x) => x.id === a.id));
  ok(await call('POST', `/admin/articles/${a.id}/remove`, tokens.admin, { reason: 'Outdated' }));
  assert.equal((await call('GET', `/articles/${a.id}`, tokens.student)).status, 404);
});

test('mood check-ins, insights and encrypted journal (FR9)', async () => {
  const r = ok(await call('POST', '/mood', tokens.student, { mood: 1, factors: ['Exams'], note: 'Tough day' }), 201);
  assert.ok(r.streak >= 1);
  assert.equal(r.suggestion.kind, 'counsellor');
  ok(await call('GET', '/mood/history?range=week', tokens.student));
  ok(await call('GET', '/mood/insights?range=month', tokens.student));
  const j = ok(await call('POST', '/mood/journal', tokens.student, { title: 'Secret thoughts', body: 'Nobody else reads this', mood: 2, tags: ['Health'] }), 201).entry;
  assert.ok(ok(await call('GET', '/mood/journal?q=nobody', tokens.student)).entries.some((e) => e.id === j.id));
  // Stored encrypted at rest.
  const { JournalEntry } = require('../src/models');
  const raw = await JournalEntry.collection.findOne({ _id: new (require('mongoose').Types.ObjectId)(j.id) });
  assert.ok(String(raw.body).startsWith('enc:v1:'));
  ok(await call('DELETE', `/mood/journal/${j.id}`, tokens.student));
  // Counsellors can't read mood data.
  assert.equal((await call('GET', '/mood/history', tokens.counsellor)).status, 403);
});

test('Bridge assistant escalates crisis messages to 1926 (FR10, FR8)', async () => {
  const normal = ok(await call('POST', '/wellness/bridge', tokens.student, { text: 'I feel a bit stressed about exams' }), 201);
  assert.equal(normal.escalate, false);
  const crisis = ok(await call('POST', '/wellness/bridge', tokens.student, { text: 'I don’t want to live anymore' }), 201);
  assert.equal(crisis.escalate, true);
  assert.match(crisis.reply.text, /1926/);
  for (const t of ["I can't go on", 'thinking about self-harm', 'I want to end my life', 'do not want to be alive']) {
    assert.equal(ok(await call('POST', '/wellness/bridge', tokens.student, { text: t }), 201).escalate, true, t);
  }
  ok(await call('POST', '/wellness/events', tokens.student, { kind: 'helpline_tap', detail: '1926' }), 201);
  ok(await call('DELETE', '/wellness/bridge', tokens.student));
});

test('admin: verification, roles, account status, settings and audit (FR11)', async () => {
  const apps = ok(await call('GET', '/admin/verifications?role=counsellor&status=pending', tokens.admin)).applications;
  const a1 = apps[0];
  const detail = ok(await call('GET', `/admin/verifications/${a1.id}`, tokens.admin)).application;
  const doc = detail.verification.documents[0];
  ok(await call('PATCH', `/admin/verifications/${a1.id}/documents/${doc.id}`, tokens.admin, { checked: true }));
  const link = ok(await call('POST', '/download', tokens.admin, { target: 'document', ownerId: a1.id, docId: doc.id }), 201);
  const file = await fetch(base.replace('/api', '') + link.path);
  assert.equal(file.status, 200);
  assert.equal(file.headers.get('content-type'), 'application/pdf');
  assert.equal((await fetch(base.replace('/api', '') + link.path)).status, 404, 'download links are single-use');
  ok(await call('POST', `/admin/verifications/${a1.id}/approve`, tokens.admin));
  const again = await call('POST', `/admin/verifications/${a1.id}/approve`, tokens.admin);
  assert.equal(again.status, 409);
  const a2 = apps[1];
  ok(await call('POST', `/admin/verifications/${a2.id}/request-changes`, tokens.admin, { items: ['National ID'], message: 'Please re-upload' }));
  const docApps = ok(await call('GET', '/admin/verifications?role=doctor&status=pending', tokens.admin)).applications;
  ok(await call('POST', `/admin/verifications/${docApps[0].id}/reject`, tokens.admin, { reason: 'SLMC registration not found', message: 'Could not verify' }));

  const users = ok(await call('GET', '/admin/users?role=student&q=nimal', tokens.admin)).users;
  const u = users[0];
  const role = ok(await call('PATCH', `/admin/users/${u.id}/role`, tokens.admin, { role: 'admin' }));
  assert.equal(role.to, 'Admin');
  const noReason = await call('PATCH', `/admin/users/${u.id}/status`, tokens.admin, { status: 'deactivated' });
  assert.equal(noReason.status, 400);
  ok(await call('PATCH', `/admin/users/${u.id}/status`, tokens.admin, { status: 'deactivated', reason: 'Duplicate account' }));
  ok(await call('PATCH', '/admin/settings/appointments', tokens.admin, { bookingWindowDays: 14 }));
  const cfg = ok(await call('GET', '/admin/settings', tokens.admin)).settings;
  assert.equal(cfg.appointments.bookingWindowDays, 14);
  // Policy floor can't be lowered.
  ok(await call('PATCH', '/admin/settings/privacy', tokens.admin, { minReportGroupSize: 1 }));
  assert.equal(ok(await call('GET', '/admin/settings', tokens.admin)).settings.privacy.minReportGroupSize, 10);
  const logs = ok(await call('GET', '/admin/logs?category=verification', tokens.admin)).logs;
  assert.ok(logs.length >= 3);
  // Non-admins are refused.
  assert.equal((await call('GET', '/admin/users', tokens.counsellor)).status, 403);
});

test('reports are anonymised and exportable (FR12)', async () => {
  const o = ok(await call('GET', '/admin/reports/overview?range=semester', tokens.admin));
  assert.equal(o.minGroup, 10);
  for (const s of ['appointments', 'types', 'usage', 'wellness', 'users']) ok(await call('GET', `/admin/reports/${s}?range=semester`, tokens.admin));
  const csv = ok(await call('POST', '/download', tokens.admin, { target: 'report', query: { range: 'semester', format: 'csv', sections: 'appointments,usage' } }), 201);
  const res = await fetch(base.replace('/api', '') + csv.path);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /^Section,Metric,Value/);
});

test('sessions: sign-out revokes the token and staff verification gate', async () => {
  const t = await login('it23004418@my.sliit.lk');
  ok(await call('POST', '/auth/logout', t));
  assert.equal((await call('GET', '/auth/me', t)).status, 401);
  // Unverified staff can sign in but not use staff features.
  const r = ok(await call('POST', '/auth/register', null, { role: 'counsellor', name: 'New Counsellor', email: 'new.c@sliit.lk', password: 'abcdefg1', professional: { title: 'Counsellor', registrationNo: 'SLNCC 9999' }, agreePrivacy: true }), 201);
  const v = ok(await call('POST', '/auth/verify-email', null, { email: r.email, code: r.devOtp }));
  const gated = await call('GET', '/staff/dashboard', v.token);
  assert.equal(gated.status, 403);
  assert.equal(gated.body.error.code, 'NOT_VERIFIED');
});

test('music library and article covers (Cloudinary not configured in tests)', async () => {
  const lib = ok(await call('GET', '/music', tokens.student));
  assert.equal(lib.tracks.length, 8);
  assert.equal(lib.tracks[0].title, 'Rain on the Library Roof');
  assert.equal(lib.tracks[0].url, null); // demo tracks have no audio yet
  assert.deepEqual(lib.categories, ['Sleep', 'Focus', 'Rain', 'Nature', 'Lo-fi']);

  const upload = (path, token, name, type, fields = {}, method = 'POST') => {
    const form = new FormData();
    for (const [k, v] of Object.entries(fields)) form.append(k, v);
    form.append('file', new Blob([Buffer.from('ID3fake')], { type }), name);
    return fetch(base + path, { method, headers: { Authorization: `Bearer ${token}` }, body: form }).then(async (r) => ({ status: r.status, body: await r.json() }));
  };
  // Only Student Affairs manages music.
  assert.equal((await upload('/music', tokens.student, 'a.mp3', 'audio/mpeg', { title: 'Song', category: 'Sleep' })).status, 403);
  const wrongType = await upload('/music', tokens.admin, 'a.pdf', 'application/pdf', { title: 'Song', category: 'Sleep' });
  assert.equal(wrongType.body.error.code, 'BAD_FILE');
  const noStorage = await upload('/music', tokens.admin, 'a.mp3', 'audio/mpeg', { title: 'Song', category: 'Sleep' });
  assert.equal(noStorage.status, 400);
  assert.equal(noStorage.body.error.code, 'STORAGE_NOT_CONFIGURED');

  const id = lib.tracks[0].id;
  const edited = ok(await call('PATCH', `/music/${id}`, tokens.admin, { title: 'Rain Again', category: 'Sleep' }));
  assert.equal(edited.track.icon, 'bedtime');
  ok(await call('DELETE', `/music/${id}`, tokens.admin));
  assert.equal(ok(await call('GET', '/music', tokens.student)).tracks.length, 7);

  // Covers: only the author, only before publishing.
  const mine = ok(await call('GET', '/articles/mine', tokens.counsellor)).articles;
  const live = mine.find((a) => a.status === 'published');
  assert.equal(live.coverUrl, null);
  const locked = await upload(`/articles/${live.id}/cover`, tokens.counsellor, 'c.png', 'image/png', {}, 'PUT');
  assert.equal(locked.status, 409);
  const draft = ok(await call('POST', '/articles', tokens.counsellor, { title: 'A cover test article', category: 'Sleep', body: 'x'.repeat(60) }), 201).article;
  const gif = await upload(`/articles/${draft.id}/cover`, tokens.counsellor, 'c.gif', 'image/gif', {}, 'PUT');
  assert.equal(gif.body.error.code, 'BAD_FILE');
  assert.equal((await upload(`/articles/${draft.id}/cover`, tokens.counsellor, 'c.png', 'image/png', {}, 'PUT')).body.error.code, 'STORAGE_NOT_CONFIGURED');
});
