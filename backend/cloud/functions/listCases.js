const caseService = require('../services/caseService');
const { requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Lists every case the caller owns, most recent first -- the single
 * source of truth for the client's "Recent Cases" list. The client no
 * longer keeps its own local index of which cases exist; it always
 * reflects whatever this returns.
 */
Parse.Cloud.define('mmListCases', async (request) => {
  const startedAt = Date.now();
  try {
    const ownerId = requireAuthenticatedUser(request);
    const cases = await caseService.listCases({ ownerId });

    logger.info({ function: 'mmListCases', count: cases.length, latencyMs: Date.now() - startedAt });

    return { cases };
  } catch (err) {
    logger.error({ function: 'mmListCases', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
