import React from 'react';

export const Loader = ({ message = 'Loading MindBridge…', fullScreen = false }) => {
  if (fullScreen) {
    return (
      <div
        style={{
          position: 'fixed',
          inset: 0,
          background: 'var(--bg-app)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 9999,
          gap: '1rem',
        }}
      >
        <div className="spinner" style={{ width: 44, height: 44, borderWidth: 4 }} />
        <p style={{ color: 'var(--text-muted)', fontWeight: 500, fontSize: '0.95rem' }}>
          {message}
        </p>
      </div>
    );
  }

  return (
    <div className="loading-screen">
      <div className="spinner" style={{ width: 36, height: 36, borderWidth: 3 }} />
      <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>{message}</p>
    </div>
  );
};

export default Loader;
