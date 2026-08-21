const caseService = require('../services/caseService');
const { requireAuthenticatedUser, requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Drives the paywall's first-case-free decision on the client. `deviceId`
 * is required -- eligibility depends on both the account's case count and
 * whether this device has redeemed a free case before, even under a
 * different (possibly deleted) account. Callers must never be able to ask
 * about another user's cases.
 */
Parse.Cloud.define('mmCheckFreeCaseEligibility', async (request) => {
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const deviceId = requireNonEmptyString(params.deviceId, 'deviceId');
    const result = await caseService.checkFreeCaseEligibility({ ownerId, deviceId });

    logger.info({ function: 'mmCheckFreeCaseEligibility', ownerId, eligible: result.eligible });

    return result;
  } catch (err) {
    logger.error({ function: 'mmCheckFreeCaseEligibility', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
