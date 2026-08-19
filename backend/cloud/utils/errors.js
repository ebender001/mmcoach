/**
 * Application-level error types, independent of Parse. Keeping these
 * Parse-free makes services and AI modules testable without the Parse SDK.
 * Cloud Functions convert these to Parse.Error via toParseError() at the
 * boundary, right before returning to the client.
 */
class AppError extends Error {
  constructor(message, code = 'INTERNAL_ERROR') {
    super(message);
    this.name = 'AppError';
    this.code = code;
  }
}

class ValidationError extends AppError {
  constructor(message) {
    super(message, 'VALIDATION_ERROR');
    this.name = 'ValidationError';
  }
}

class NotFoundError extends AppError {
  constructor(message) {
    super(message, 'NOT_FOUND');
    this.name = 'NotFoundError';
  }
}

class InvalidStateError extends AppError {
  constructor(message) {
    super(message, 'INVALID_STATE');
    this.name = 'InvalidStateError';
  }
}

class AuthenticationError extends AppError {
  constructor(message) {
    super(message, 'AUTHENTICATION_ERROR');
    this.name = 'AuthenticationError';
  }
}

class AIProviderError extends AppError {
  constructor(message) {
    super(message, 'AI_PROVIDER_ERROR');
    this.name = 'AIProviderError';
  }
}

class AIResponseError extends AppError {
  constructor(message) {
    super(message, 'AI_RESPONSE_ERROR');
    this.name = 'AIResponseError';
  }
}

/**
 * Maps an AppError (or unknown error) to a Parse.Error so Cloud Functions
 * never leak internal messages/stack traces to the client. Reads the global
 * `Parse` at call time so this file has no hard dependency on the Parse SDK.
 */
function toParseError(err) {
  if (typeof Parse === 'undefined' || !Parse.Error) {
    return err;
  }

  if (err instanceof ValidationError) {
    return new Parse.Error(Parse.Error.VALIDATION_ERROR, err.message);
  }
  if (err instanceof NotFoundError) {
    return new Parse.Error(Parse.Error.OBJECT_NOT_FOUND, err.message);
  }
  if (err instanceof InvalidStateError) {
    return new Parse.Error(Parse.Error.OPERATION_FORBIDDEN, err.message);
  }
  if (err instanceof AuthenticationError) {
    return new Parse.Error(Parse.Error.INVALID_SESSION_TOKEN, err.message);
  }
  if (err instanceof AIProviderError || err instanceof AIResponseError) {
    return new Parse.Error(Parse.Error.INTERNAL_SERVER_ERROR, err.message);
  }
  if (err instanceof AppError) {
    return new Parse.Error(Parse.Error.INTERNAL_SERVER_ERROR, err.message);
  }

  return new Parse.Error(Parse.Error.INTERNAL_SERVER_ERROR, 'Internal server error.');
}

module.exports = {
  AppError,
  ValidationError,
  NotFoundError,
  InvalidStateError,
  AuthenticationError,
  AIProviderError,
  AIResponseError,
  toParseError,
};
