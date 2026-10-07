/**
 * MindBridge Platform Constants
 * Shared across all 4 group members' modules
 */

export const ROLES = {
  STUDENT: 'student',
  COUNSELLOR: 'counsellor',
  DOCTOR: 'doctor',
  ADMIN: 'admin',
};

export const APPOINTMENT_STATUS = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
};

export const REFERRAL_STATUS = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  COMPLETED: 'completed',
  REJECTED: 'rejected',
};

export const USER_STATUS = {
  ACTIVE: 'active',
  PENDING: 'pending',
  SUSPENDED: 'suspended',
};

export const ARTICLE_CATEGORIES = [
  'Stress & Anxiety',
  'Depression & Mood',
  'Academic Pressure',
  'Sleep & Fatigue',
  'Relationships & Social',
  'Mindfulness & Meditation',
  'General Wellness',
];

export const EMERGENCY_CONTACTS = {
  NATIONAL_MENTAL_HEALTH: {
    name: 'National Mental Health Helpline',
    number: '1926',
    available: '24/7 Free & Confidential',
  },
  SUWA_SERIYA: {
    name: 'Suwa Seriya Ambulance Service',
    number: '1990',
    available: '24/7 Emergency Medical Response',
  },
  SUMITHRAYO: {
    name: 'Sumithrayo Befrienders',
    number: '011 269 2511',
    available: 'Emotional Support',
  },
};

export const STORAGE_KEYS = {
  TOKEN: 'mindbridge_token',
  USER: 'mindbridge_user',
  THEME: 'mindbridge_theme',
};
