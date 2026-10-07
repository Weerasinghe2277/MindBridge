import React from 'react';
import { EMERGENCY_CONTACTS } from '../../utils/constants';
import { Phone, Shield, Heart } from 'lucide-react';

export const Footer = () => {
  return (
    <footer
      style={{
        background: 'var(--bg-surface)',
        borderTop: '1px solid var(--border-light)',
        padding: '2rem 1.5rem 1.5rem',
        marginTop: 'auto',
      }}
    >
      <div className="container">
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
            gap: '2rem',
            marginBottom: '1.5rem',
          }}
        >
          {/* Brand Info */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.75rem' }}>
              <Heart size={20} color="var(--primary-600)" />
              <span style={{ fontFamily: 'Outfit', fontWeight: 800, fontSize: '1.1rem' }}>
                MindBridge
              </span>
            </div>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', lineHeight: 1.6 }}>
              A safe, confidential mental health check-in, counselling appointment, and doctor referral
              support platform built for university students and healthcare professionals.
            </p>
          </div>

          {/* Emergency Hotlines */}
          <div>
            <h4 style={{ fontSize: '0.9rem', marginBottom: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
              Immediate Help Hotlines
            </h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', fontSize: '0.85rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Phone size={14} color="var(--primary-600)" />
                <strong>{EMERGENCY_CONTACTS.NATIONAL_MENTAL_HEALTH.number}</strong>
                <span style={{ color: 'var(--text-muted)' }}>({EMERGENCY_CONTACTS.NATIONAL_MENTAL_HEALTH.name})</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Phone size={14} color="var(--primary-600)" />
                <strong>{EMERGENCY_CONTACTS.SUWA_SERIYA.number}</strong>
                <span style={{ color: 'var(--text-muted)' }}>({EMERGENCY_CONTACTS.SUWA_SERIYA.name})</span>
              </div>
            </div>
          </div>

          {/* Privacy & Confidentiality Notice */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
              <Shield size={16} color="var(--accent-teal)" />
              <h4 style={{ fontSize: '0.9rem' }}>Privacy & Data Security</h4>
            </div>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', lineHeight: 1.5 }}>
              Your check-ins and appointments are strictly private. Medical referrals are only shared
              with assigned certified physicians.
            </p>
          </div>
        </div>

        <div
          style={{
            borderTop: '1px solid var(--border-light)',
            paddingTop: '1rem',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            fontSize: '0.8rem',
            color: 'var(--text-muted)',
            flexWrap: 'wrap',
            gap: '0.5rem',
          }}
        >
          <div>© {new Date().getFullYear()} MindBridge Health Services. University IT Project.</div>
          <div>All 4 modules integrated: Appointments • Approvals • Mood • Articles & Doctors</div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
