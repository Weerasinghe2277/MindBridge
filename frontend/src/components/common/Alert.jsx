import React from 'react';
import { CheckCircle, AlertTriangle, AlertCircle, Info, X } from 'lucide-react';

export const Alert = ({
  type = 'info', // 'success' | 'warning' | 'danger' | 'info'
  message,
  children,
  onClose,
  className = '',
}) => {
  const icons = {
    success: <CheckCircle size={18} style={{ flexShrink: 0 }} />,
    warning: <AlertTriangle size={18} style={{ flexShrink: 0 }} />,
    danger: <AlertCircle size={18} style={{ flexShrink: 0 }} />,
    info: <Info size={18} style={{ flexShrink: 0 }} />,
  };

  return (
    <div className={`alert alert-${type} ${className}`.trim()} role="alert">
      {icons[type] || icons.info}
      <div style={{ flex: 1 }}>{children || message}</div>
      {onClose && (
        <button
          onClick={onClose}
          style={{
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            padding: 0,
            color: 'inherit',
            opacity: 0.7,
            display: 'flex',
          }}
          aria-label="Close alert"
        >
          <X size={16} />
        </button>
      )}
    </div>
  );
};

export default Alert;
