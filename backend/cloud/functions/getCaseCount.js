const caseService = require('../services/caseService');
const { requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Drives the paywall's first-case-free decision on the client. Deliberately
 * takes no params beyond the authenticated user -- callers must never be
 * able to ask about another user's case count.
 */
Parse.Cloud.define('mmGetCaseCount', async (request) => {
  try {
    const ownerId = requireAuthenticatedUser(request);
    const result = await caseService.getCaseCount({ ownerId });

    logger.info({ function: 'mmGetCaseCount', ownerId, caseCount: result.caseCount });

    return result;
  } catch (err) {
    logger.error({ function: 'mmGetCaseCount', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
