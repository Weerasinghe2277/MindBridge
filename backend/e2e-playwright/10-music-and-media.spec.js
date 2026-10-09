const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('10 - Music Library & Media Restrictions', () => {
  let studentToken;
  let adminToken;
  let counsellorToken;

  test.beforeAll(async ({ request }) => {
    studentToken = await getRoleToken(request, 'student');
    adminToken = await getRoleToken(request, 'admin');
    counsellorToken = await getRoleToken(request, 'counsellor');
  });

  test('Student accesses ambient music catalog and categories', async ({ request }) => {
    const res = await request.get('/api/music', {
      headers: authHeader(studentToken),
    });
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(Array.isArray(body.tracks)).toBe(true);
    expect(body.tracks.length).toBeGreaterThanOrEqual(1);
    expect(Array.isArray(body.categories)).toBe(true);
    expect(body.categories).toContain('Sleep');
    expect(body.categories).toContain('Focus');
  });

  test('Students cannot upload music tracks (Admin restricted)', async ({ request }) => {
    const forbiddenRes = await request.post('/api/music', {
      headers: authHeader(studentToken),
      data: { title: 'Unauthorized track', category: 'Sleep' },
    });
    expect(forbiddenRes.status()).toBe(403);
  });

  test('Admin edits music track metadata and removes track', async ({ request }) => {
    const listRes = await request.get('/api/music', { headers: authHeader(studentToken) });
    const tracks = (await listRes.json()).tracks;
    expect(tracks.length).toBeGreaterThanOrEqual(1);

    const track = tracks[0];

    // Edit track
    const editRes = await request.patch(`/api/music/${track.id}`, {
      headers: authHeader(adminToken),
      data: { title: 'Rain on the Rooftop Updated', category: 'Sleep' },
    });
    expect(editRes.status()).toBe(200);
    const updated = (await editRes.json()).track;
    expect(updated.title).toBe('Rain on the Rooftop Updated');

    // Delete track
    const deleteRes = await request.delete(`/api/music/${track.id}`, {
      headers: authHeader(adminToken),
    });
    expect(deleteRes.status()).toBe(200);
  });

  test('Profile photo deletion and authorization checks', async ({ request }) => {
    // Students cannot upload profile photo to staff endpoint
    const studentUploadRes = await request.put('/api/me/photo', {
      headers: authHeader(studentToken),
      data: {},
    });
    expect(studentUploadRes.status()).toBe(403);

    // Counsellor can remove their photo
    const deletePhotoRes = await request.delete('/api/me/photo', {
      headers: authHeader(counsellorToken),
    });
    expect(deletePhotoRes.status()).toBe(200);
  });
});
