const { ValidationError, AuthenticationError } = require('./errors');

function requireNonEmptyString(value, fieldName) {
  if (typeof value !== 'string') {
    throw new ValidationError(`${fieldName} is required and must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new ValidationError(`${fieldName} must not be empty.`);
  }
  return trimmed;
}

/**
 * A narrative is "meaningful" if it's a non-trivial length. This is a cheap
 * heuristic, not a clinical-content check -- the AI is responsible for
 * deciding whether the content is usable.
 */
function requireMeaningfulNarrative(value, { minLength = 20, fieldName = 'narrative' } = {}) {
  const trimmed = requireNonEmptyString(value, fieldName);
  if (trimmed.length < minLength) {
    throw new ValidationError(
      `${fieldName} is too short to describe a case (minimum ${minLength} characters).`
    );
  }
  return trimmed;
}

/**
 * Every MMCase-touching Cloud Function must resolve the owner from the
 * *authenticated request's* session, never from a client-supplied param --
 * this is the one place that boundary is enforced. `request.user` is
 * populated by Parse Server from the caller's session token; there is no
 * client input involved.
 */
function requireAuthenticatedUser(request) {
  const userId = request && request.user && request.user.id;
  if (!userId) {
    throw new AuthenticationError('Sign in required.');
  }
  return userId;
}

/**
 * Gate for admin-only Cloud Functions that have no legitimate per-user
 * scope (e.g. a cross-user cost export) -- compared against
 * `MMCOACH_ADMIN_SECRET`, never against a Parse.User session. Fails
 * closed if the env var isn't configured, rather than treating an unset
 * secret as "no check needed".
 */
function requireAdminSecret(request) {
  const configured = process.env.MMCOACH_ADMIN_SECRET;
  const provided = request && request.params && request.params.adminSecret;
  if (!configured) {
    throw new AuthenticationError('Admin export is not configured.');
  }
  if (!provided || provided !== configured) {
    throw new AuthenticationError('Invalid admin credentials.');
  }
}

module.exports = {
  requireNonEmptyString,
  requireMeaningfulNarrative,
  requireAuthenticatedUser,
  requireAdminSecret,
};
