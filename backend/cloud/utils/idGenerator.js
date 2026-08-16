const crypto = require('crypto');

/**
 * Generates an id for conversation questions. Uses crypto.randomUUID when
 * available (Node 14.17+) and falls back to a timestamp+random id otherwise
 * so this never depends on an external package.
 */
function generateId(prefix = 'id') {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

module.exports = { generateId };
