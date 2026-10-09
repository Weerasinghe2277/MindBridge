const { test, expect } = require('@playwright/test');
const { getRoleToken, authHeader } = require('./helpers/auth');

test.describe('06 - Psychoeducational Articles Management & Publishing', () => {
  let counsellorToken;
  let adminToken;
  let studentToken;

  test.beforeAll(async ({ request }) => {
    counsellorToken = await getRoleToken(request, 'counsellor');
    adminToken = await getRoleToken(request, 'admin');
    studentToken = await getRoleToken(request, 'student');
  });

  test('Article authoring, admin moderation, publishing, live revision, and student bookmarks', async ({ request }) => {
    // 1. Validation: Body too short (< 60 chars) rejected
    const shortRes = await request.post('/api/articles', {
      headers: authHeader(counsellorToken),
      data: { title: 'Quick tip', category: 'Stress', body: 'Too short text' },
    });
    expect(shortRes.status()).toBe(400);

    // 2. Counsellor creates valid article draft
    const createRes = await request.post('/api/articles', {
      headers: authHeader(counsellorToken),
      data: {
        title: 'Effective Mindfulness Techniques for University Students',
        category: 'Stress',
        body: 'Mindfulness and box breathing exercises can reduce acute examination stress and significantly enhance memory retention during study sessions.',
      },
    });
    expect(createRes.status()).toBe(201);
    const article = (await createRes.json()).article;

    // 3. Submit article for review
    const submitRes = await request.post(`/api/articles/${article.id}/submit`, {
      headers: authHeader(counsellorToken),
    });
    expect(submitRes.status()).toBe(200);

    // 4. Admin rejects with feedback
    const rejectRes = await request.post(`/api/admin/articles/${article.id}/reject`, {
      headers: authHeader(adminToken),
      data: { reason: 'Content guidelines', feedback: 'Please add helpline contact at the end.' },
    });
    expect(rejectRes.status()).toBe(200);

    // 5. Counsellor edits and resubmits
    await request.put(`/api/articles/${article.id}`, {
      headers: authHeader(counsellorToken),
      data: {
        title: 'Effective Mindfulness Techniques for University Students',
        category: 'Stress',
        body: 'Mindfulness and box breathing exercises can reduce acute examination stress. If symptoms persist, reach out to university counselling or dial 1926.',
      },
    });
    await request.post(`/api/articles/${article.id}/submit`, { headers: authHeader(counsellorToken) });

    // 6. Admin approves
    const approveRes = await request.post(`/api/admin/articles/${article.id}/approve`, {
      headers: authHeader(adminToken),
    });
    expect(approveRes.status()).toBe(200);

    // 7. Student reads published article
    const studentReadRes = await request.get(`/api/articles/${article.id}`, {
      headers: authHeader(studentToken),
    });
    expect(studentReadRes.status()).toBe(200);
    const pubArticle = (await studentReadRes.json()).article;
    expect(pubArticle.status).toBe('published');

    // 8. Student bookmarks/saves article
    const saveRes = await request.post(`/api/articles/${article.id}/save`, {
      headers: authHeader(studentToken),
    });
    expect(saveRes.status()).toBe(200);

    const savedListRes = await request.get('/api/articles/saved', {
      headers: authHeader(studentToken),
    });
    expect(savedListRes.status()).toBe(200);
    const savedList = (await savedListRes.json()).articles;
    expect(savedList.some((a) => a.id === article.id)).toBe(true);

    // 9. Admin removes article
    const removeRes = await request.post(`/api/admin/articles/${article.id}/remove`, {
      headers: authHeader(adminToken),
      data: { reason: 'Archived for seasonal rotation' },
    });
    expect(removeRes.status()).toBe(200);

    const checkRemovedRes = await request.get(`/api/articles/${article.id}`, {
      headers: authHeader(studentToken),
    });
    expect(checkRemovedRes.status()).toBe(404);
  });
});
