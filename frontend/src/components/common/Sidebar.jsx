import React from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { ROLES } from '../../utils/constants';
import {
  LayoutDashboard,
  CalendarCheck,
  Smile,
  BookOpen,
  Stethoscope,
  Users,
  ShieldCheck,
  Clock,
  Sparkles,
} from 'lucide-react';

export const Sidebar = ({ isOpen, onClose }) => {
  const { user } = useAuth();
  const role = user?.role || ROLES.STUDENT;

  // Build navigation items tailored to user role and team member modules
  const getNavItems = () => {
    const common = [
      {
        to: '/dashboard',
        label: 'Dashboard',
        icon: <LayoutDashboard size={18} />,
      },
    ];

    if (role === ROLES.STUDENT) {
      return [
        ...common,
        {
          to: '/appointments',
          label: 'Appointments',
          badge: 'M1',
          icon: <CalendarCheck size={18} />,
        },
        {
          to: '/mood-checkin',
          label: 'Mood Check-in',
          badge: 'M3',
          icon: <Smile size={18} />,
        },
        {
          to: '/articles',
          label: 'Wellness Articles',
          badge: 'M4',
          icon: <BookOpen size={18} />,
        },
        {
          to: '/doctor-referrals',
          label: 'Doctor Referrals',
          badge: 'M4',
          icon: <Stethoscope size={18} />,
        },
      ];
    }

    if (role === ROLES.COUNSELLOR) {
      return [
        ...common,
        {
          to: '/appointments',
          label: 'My Appointments',
          badge: 'M1',
          icon: <CalendarCheck size={18} />,
        },
        {
          to: '/appointments',
          label: 'Manage Availability',
          badge: 'M1',
          icon: <Clock size={18} />,
        },
        {
          to: '/doctor-referrals',
          label: 'Refer to Doctor',
          badge: 'M4',
          icon: <Stethoscope size={18} />,
        },
        {
          to: '/articles',
          label: 'Publish Article',
          badge: 'M4',
          icon: <BookOpen size={18} />,
        },
      ];
    }

    if (role === ROLES.DOCTOR) {
      return [
        ...common,
        {
          to: '/doctor-referrals',
          label: 'Patient Referrals',
          badge: 'M4',
          icon: <Stethoscope size={18} />,
        },
        {
          to: '/articles',
          label: 'Medical Articles',
          badge: 'M4',
          icon: <BookOpen size={18} />,
        },
      ];
    }

    if (role === ROLES.ADMIN) {
      return [
        ...common,
        {
          to: '/admin/users',
          label: 'User Management',
          badge: 'M2',
          icon: <Users size={18} />,
        },
        {
          to: '/admin/users',
          label: 'Counsellor Approvals',
          badge: 'M2',
          icon: <ShieldCheck size={18} />,
        },
        {
          to: '/articles',
          label: 'Manage Articles',
          badge: 'M4',
          icon: <BookOpen size={18} />,
        },
        {
          to: '/appointments',
          label: 'All Appointments',
          badge: 'M1',
          icon: <CalendarCheck size={18} />,
        },
      ];
    }

    return common;
  };

  const navItems = getNavItems();

  return (
    <>
      {/* Mobile Backdrop */}
      {isOpen && (
        <div
          onClick={onClose}
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(0,0,0,0.5)',
            zIndex: 40,
            display: 'block',
          }}
        />
      )}

      <aside
        style={{
          width: '260px',
          background: 'var(--bg-sidebar)',
          color: 'var(--text-sidebar)',
          display: 'flex',
          flexDirection: 'column',
          borderRight: '1px solid var(--border-light)',
          flexShrink: 0,
          transition: 'transform var(--transition-normal)',
          zIndex: 45,
        }}
      >
        <div style={{ padding: '1.25rem 1.5rem', borderBottom: '1px solid #1E293B' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <Sparkles size={16} color="var(--primary-400)" />
            <span style={{ fontSize: '0.8rem', fontWeight: 700, color: '#CBD5E1', textTransform: 'uppercase', letterSpacing: '0.8px' }}>
              Navigation Portal
            </span>
          </div>
        </div>

        <nav style={{ padding: '1rem 0.75rem', flex: 1, display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
          {navItems.map((item, idx) => (
            <NavLink
              key={idx}
              to={item.to}
              onClick={onClose}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: '0.75rem',
                padding: '0.75rem 1rem',
                borderRadius: 'var(--radius-md)',
                color: isActive ? 'var(--text-sidebar-light)' : 'var(--text-sidebar)',
                background: isActive ? 'var(--bg-sidebar-active)' : 'transparent',
                fontWeight: isActive ? 600 : 500,
                fontSize: '0.9rem',
                textDecoration: 'none',
                transition: 'all var(--transition-fast)',
              })}
            >
              <span>{item.icon}</span>
              <span style={{ flex: 1 }}>{item.label}</span>
              {item.badge && (
                <span
                  style={{
                    fontSize: '0.65rem',
                    padding: '0.1rem 0.4rem',
                    background: 'rgba(255,255,255,0.12)',
                    borderRadius: 'var(--radius-full)',
                    color: '#94A3B8',
                    fontWeight: 700,
                  }}
                  title={`Feature Module ${item.badge}`}
                >
                  {item.badge}
                </span>
              )}
            </NavLink>
          ))}
        </nav>

        {/* Member Feature Info Footer in Sidebar */}
        <div
          style={{
            padding: '1rem',
            margin: '0.75rem',
            background: 'rgba(255, 255, 255, 0.04)',
            borderRadius: 'var(--radius-md)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            fontSize: '0.75rem',
            color: '#94A3B8',
            lineHeight: 1.4,
          }}
        >
          <div style={{ fontWeight: 700, color: '#E2E8F0', marginBottom: '0.35rem' }}>
            MindBridge Group Team
          </div>
          <div>M1: Appointments & Availability</div>
          <div>M2: Users & Approvals</div>
          <div>M3: Mood Tracker & Sessions</div>
          <div>M4: Articles & Doctor Referrals</div>
        </div>
      </aside>
    </>
  );
};

export default Sidebar;
