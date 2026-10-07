class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const badRequest = (message, code = 'BAD_REQUEST', details) => new ApiError(400, code, message, details);
const unauthorized = (message = 'Please sign in to continue.', code = 'UNAUTHORIZED') => new ApiError(401, code, message);
const forbidden = (message = 'You don’t have permission to do that.', code = 'FORBIDDEN') => new ApiError(403, code, message);
const notFound = (message = 'Not found.', code = 'NOT_FOUND') => new ApiError(404, code, message);
const conflict = (message, code = 'CONFLICT', details) => new ApiError(409, code, message, details);

module.exports = { ApiError, badRequest, unauthorized, forbidden, notFound, conflict };
