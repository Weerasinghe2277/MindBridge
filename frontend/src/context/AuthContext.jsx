import React, { createContext, useContext, useState, useEffect } from 'react';
import { STORAGE_KEYS, ROLES } from '../utils/constants';
import { authApi } from '../services/endpoints';

const AuthContext = createContext(null);

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEYS.USER);
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
  });

  const [token, setToken] = useState(() => localStorage.getItem(STORAGE_KEYS.TOKEN));
  const [loading, setLoading] = useState(true);

  // Sync token & user with storage
  useEffect(() => {
    const handleUnauthorized = () => {
      logout();
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    setLoading(false);

    return () => {
      window.removeEventListener('auth:unauthorized', handleUnauthorized);
    };
  }, []);

  const saveAuthSession = (authToken, userData) => {
    setToken(authToken);
    setUser(userData);
    localStorage.setItem(STORAGE_KEYS.TOKEN, authToken);
    localStorage.setItem(STORAGE_KEYS.USER, JSON.stringify(userData));
  };

  const login = async (email, password) => {
    try {
      const res = await authApi.login({ email, password });
      const { token: receivedToken, user: receivedUser } = res.data;
      saveAuthSession(receivedToken, receivedUser);
      return { success: true, user: receivedUser };
    } catch (err) {
      return {
        success: false,
        error: err.response?.data?.error?.message || err.response?.data?.message || 'Login failed. Please check your credentials.',
      };
    }
  };

  /**
   * Quick Demo Login helper for local development and UI testing
   * Allows team members to test student, counsellor, doctor, and admin views instantly
   */
  const demoLogin = (role = ROLES.STUDENT) => {
    const mockUsers = {
      [ROLES.STUDENT]: {
        _id: 'demo-student-1',
        name: 'Kamal Perera',
        email: 'kamal.p@my.sliit.lk',
        studentId: 'IT23104520',
        role: ROLES.STUDENT,
        avatar: null,
      },
      [ROLES.COUNSELLOR]: {
        _id: 'demo-counsellor-1',
        name: 'Dr. Nirmala Silva',
        email: 'nirmala.s@mindbridge.lk',
        role: ROLES.COUNSELLOR,
        specialization: 'Cognitive Behavioral Therapy',
        avatar: null,
      },
      [ROLES.DOCTOR]: {
        _id: 'demo-doctor-1',
        name: 'Dr. Rohan Jayasinghe (MBBS, MD)',
        email: 'rohan.j@medical.lk',
        role: ROLES.DOCTOR,
        hospital: 'National Hospital / University Medical Center',
        avatar: null,
      },
      [ROLES.ADMIN]: {
        _id: 'demo-admin-1',
        name: 'System Administrator',
        email: 'admin@mindbridge.lk',
        role: ROLES.ADMIN,
        avatar: null,
      },
    };

    const targetUser = mockUsers[role] || mockUsers[ROLES.STUDENT];
    const demoToken = `demo-token-${role}-${Date.now()}`;
    saveAuthSession(demoToken, targetUser);
    return targetUser;
  };

  const register = async (userData) => {
    try {
      const res = await authApi.register(userData);
      return { success: true, data: res.data };
    } catch (err) {
      return {
        success: false,
        error: err.response?.data?.error?.message || err.response?.data?.message || 'Registration failed.',
      };
    }
  };

  const logout = () => {
    setUser(null);
    setToken(null);
    localStorage.removeItem(STORAGE_KEYS.TOKEN);
    localStorage.removeItem(STORAGE_KEYS.USER);
  };

  const hasRole = (allowedRoles) => {
    if (!user) return false;
    if (Array.isArray(allowedRoles)) {
      return allowedRoles.includes(user.role);
    }
    return user.role === allowedRoles;
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        isAuthenticated: !!token && !!user,
        loading,
        login,
        demoLogin,
        register,
        logout,
        hasRole,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
