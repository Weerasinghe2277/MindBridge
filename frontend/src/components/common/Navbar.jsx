import React from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { useTheme } from '../../context/ThemeContext';
import Badge from './Badge';
import Button from './Button';
import { getInitials } from '../../utils/helpers';
import {
  HeartPulse,
  Sun,
  Moon,
  LogOut,
  PhoneCall,
  Menu,
} from 'lucide-react';

export const Navbar = ({ onToggleSidebar }) => {
  const { user, logout } = useAuth();
  const { isDark, toggleTheme } = useTheme();

  return (
    <header
      style={{
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-light)',
        position: 'sticky',
        top: 0,
        zIndex: 50,
      }}
    >
      {/* 24/7 Helpline Banner */}
      <div className="helpline-banner">
        <PhoneCall size={14} />
        <span>In crisis? University & National Support Hotline is free & 24/7:</span>
        <span className="helpline-badge">Dial 1926</span>
      </div>

      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '0.75rem 1.5rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          {onToggleSidebar && (
            <button
              onClick={onToggleSidebar}
              className="btn btn-ghost btn-sm"
              style={{ padding: '0.4rem' }}
              aria-label="Toggle Navigation"
            >
              <Menu size={20} />
            </button>
          )}

          <Link
            to="/dashboard"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.6rem',
              textDecoration: 'none',
            }}
          >
            <div
              style={{
                width: 36,
                height: 36,
                borderRadius: 'var(--radius-md)',
                background: 'linear-gradient(135deg, var(--primary-600) 0%, var(--accent-cyan) 100%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'white',
              }}
            >
              <HeartPulse size={20} />
            </div>
            <div>
              <span
                style={{
                  fontFamily: 'Outfit, sans-serif',
                  fontWeight: 800,
                  fontSize: '1.25rem',
                  letterSpacing: '-0.3px',
                  color: 'var(--text-main)',
                }}
              >
                Mind<span style={{ color: 'var(--primary-600)' }}>Bridge</span>
              </span>
            </div>
          </Link>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          {/* Theme Toggle */}
          <Button
            variant="ghost"
            size="sm"
            onClick={toggleTheme}
            aria-label="Toggle dark mode"
            style={{ padding: '0.5rem', borderRadius: 'var(--radius-full)' }}
          >
            {isDark ? <Sun size={18} color="var(--accent-amber)" /> : <Moon size={18} />}
          </Button>

          {/* User Profile / Status */}
          {user ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <div
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: '50%',
                  background: 'var(--primary-100)',
                  color: 'var(--primary-700)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: '0.85rem',
                }}
              >
                {getInitials(user.name)}
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.2 }}>
                <span style={{ fontWeight: 600, fontSize: '0.875rem' }}>{user.name}</span>
                <Badge variant="role" style={{ marginTop: 2, fontSize: '0.68rem', alignSelf: 'flex-start' }}>
                  {user.role}
                </Badge>
              </div>

              <Button
                variant="ghost"
                size="sm"
                onClick={logout}
                title="Sign out"
                style={{ color: 'var(--text-muted)', marginLeft: '0.5rem' }}
              >
                <LogOut size={16} />
              </Button>
            </div>
          ) : (
            <div style={{ display: 'flex', gap: '0.5rem' }}>
              <Link to="/login">
                <Button variant="outline" size="sm">Sign In</Button>
              </Link>
              <Link to="/register">
                <Button variant="primary" size="sm">Register</Button>
              </Link>
            </div>
          )}
        </div>
      </div>
    </header>
  );
};

export default Navbar;
