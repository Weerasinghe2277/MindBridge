import api from './api';

/**
 * ============================================================================
 * Shared MindBridge API Services
 * Group Members can import their respective API functions from here.
 * ============================================================================
 */

// ----------------------------------------------------------------------------
// 1. Authentication & Profile APIs (Shared)
// ----------------------------------------------------------------------------
export const authApi = {
  login: (credentials) => api.post('/auth/login', credentials),
  register: (userData) => api.post('/auth/register', userData),
  getMe: () => api.get('/me'),
  updateProfile: (data) => api.patch('/me', data),
};

// ----------------------------------------------------------------------------
// 2. Member 1: Appointment & Counsellor Availability Management
// ----------------------------------------------------------------------------
export const appointmentApi = {
  getAll: (params) => api.get('/appointments', { params }),
  getById: (id) => api.get(`/appointments/${id}`),
  create: (data) => api.post('/appointments', data),
  update: (id, data) => api.put(`/appointments/${id}`, data),
  cancel: (id, reason) => api.post(`/appointments/${id}/cancel`, { reason }),
};

export const availabilityApi = {
  getMySlots: () => api.get('/staff/availability'),
  setAvailability: (data) => api.post('/staff/availability', data),
  getCounsellorSlots: (counsellorId) => api.get(`/counsellors/${counsellorId}/availability`),
};

// ----------------------------------------------------------------------------
// 3. Member 2: User Management & Counsellor Verification / Approvals
// ----------------------------------------------------------------------------
export const userApi = {
  getAllUsers: (params) => api.get('/admin/users', { params }),
  getUserById: (id) => api.get(`/admin/users/${id}`),
  updateUserRole: (id, role) => api.patch(`/admin/users/${id}/role`, { role }),
  updateUserStatus: (id, status) => api.patch(`/admin/users/${id}/status`, { status }),
  deleteUser: (id) => api.delete(`/admin/users/${id}`),
};

export const counsellorApprovalApi = {
  applyForCounsellor: (formData) => api.post('/me/counsellor-application', formData),
  getPendingApplications: () => api.get('/admin/counsellor-applications'),
  reviewApplication: (id, decision) => api.post(`/admin/counsellor-applications/${id}/review`, decision),
};

// ----------------------------------------------------------------------------
// 4. Member 3: Mood Check-in & Counselling Session Notes
// ----------------------------------------------------------------------------
export const moodApi = {
  logMood: (data) => api.post('/mood', data),
  getHistory: (params) => api.get('/mood/history', { params }),
  getAnalytics: () => api.get('/mood/analytics'),
};

export const sessionApi = {
  getSessionDetails: (appointmentId) => api.get(`/appointments/${appointmentId}/session`),
  saveSessionNotes: (appointmentId, data) => api.post(`/appointments/${appointmentId}/session`, data),
  completeSession: (appointmentId, summary) => api.post(`/appointments/${appointmentId}/session/complete`, summary),
};

// ----------------------------------------------------------------------------
// 5. Member 4: Mental Health Articles & Doctor Referral Management (Sadeepa)
// ----------------------------------------------------------------------------
export const articleApi = {
  getAll: (params) => api.get('/articles', { params }),
  getById: (id) => api.get(`/articles/${id}`),
  create: (data) => api.post('/articles', data),
  update: (id, data) => api.put(`/articles/${id}`, data),
  delete: (id) => api.delete(`/articles/${id}`),
  like: (id) => api.post(`/articles/${id}/like`),
};

export const referralApi = {
  getAll: (params) => api.get('/referrals', { params }),
  getById: (id) => api.get(`/referrals/${id}`),
  create: (data) => api.post('/referrals', data),
  updateStatus: (id, status, notes) => api.patch(`/referrals/${id}/status`, { status, notes }),
};

export const doctorApi = {
  getAvailableDoctors: () => api.get('/doctor/available'),
  getDoctorPatients: () => api.get('/doctor/patients'),
  submitDoctorReview: (referralId, report) => api.post(`/doctor/referrals/${referralId}/review`, report),
};
