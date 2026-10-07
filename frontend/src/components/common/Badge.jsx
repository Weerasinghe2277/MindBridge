import React from 'react';
import { getStatusVariant } from '../../utils/helpers';

export const Badge = ({
  children,
  variant, // 'success' | 'warning' | 'danger' | 'info' | 'role'
  status,  // optional status string like 'pending', 'active' which automatically maps to variant
  className = '',
}) => {
  const resolvedVariant = variant || (status ? getStatusVariant(status) : 'info');

  return (
    <span className={`badge badge-${resolvedVariant} ${className}`.trim()}>
      {children || status}
    </span>
  );
};

export default Badge;
