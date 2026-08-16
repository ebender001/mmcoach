const { ValidationError } = require('./errors');

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
function requireMeaningfulNarrative(value, { minLength = 20 } = {}) {
  const trimmed = requireNonEmptyString(value, 'narrative');
  if (trimmed.length < minLength) {
    throw new ValidationError(
      `narrative is too short to describe a case (minimum ${minLength} characters).`
    );
  }
  return trimmed;
}

module.exports = { requireNonEmptyString, requireMeaningfulNarrative };
