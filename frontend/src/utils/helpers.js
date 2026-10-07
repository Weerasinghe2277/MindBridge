/**
 * Shared Helper Functions for MindBridge Frontend
 */

/**
 * Format ISO date string to human-readable date
 * e.g., "Oct 7, 2026"
 */
export const formatDate = (dateString) => {
  if (!dateString) return '—';
  const date = new Date(dateString);
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  }).format(date);
};

/**
 * Format ISO date string to human-readable date and time
 * e.g., "Oct 7, 2026, 02:30 PM"
 */
export const formatDateTime = (dateString) => {
  if (!dateString) return '—';
  const date = new Date(dateString);
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

/**
 * Get initials from full name (e.g. "Sadeepa Bandara" -> "SB")
 */
export const getInitials = (name) => {
  if (!name) return 'U';
  const parts = name.trim().split(' ');
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
  return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
};

/**
 * Truncate long text with ellipsis
 */
export const truncateText = (text, maxLength = 100) => {
  if (!text || text.length <= maxLength) return text;
  return `${text.slice(0, maxLength)}…`;
};

/**
 * Safely extract error message from API response or Error object
 */
export const getErrorMessage = (error, defaultMessage = 'An unexpected error occurred.') => {
  if (!error) return defaultMessage;
  if (error.response?.data?.error?.message) {
    return error.response.data.error.message;
  }
  if (error.response?.data?.message) {
    return error.response.data.message;
  }
  if (error.message) {
    return error.message;
  }
  return defaultMessage;
};

/**
 * Map status strings to UI badge variants
 */
export const getStatusVariant = (status) => {
  switch (status?.toLowerCase()) {
    case 'active':
    case 'confirmed':
    case 'completed':
    case 'approved':
    case 'accepted':
      return 'success';

    case 'pending':
    case 'in-progress':
    case 'scheduled':
      return 'warning';

    case 'cancelled':
    case 'rejected':
    case 'suspended':
      return 'danger';

    case 'urgent':
    case 'high':
      return 'danger';

    default:
      return 'info';
  }
};
