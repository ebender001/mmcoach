const caseService = require('../services/caseService');
const { requireAuthenticatedUser, requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Marks this device as having redeemed its free first case. Called only
 * at the moment the trainee taps "Continue with Your Free Case" -- not
 * when the paywall merely checks eligibility (see mmCheckFreeCaseEligibility)
 * -- so a person who never actually uses the free case never burns it.
 */
Parse.Cloud.define('mmRedeemFreeCase', async (request) => {
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const deviceId = requireNonEmptyString(params.deviceId, 'deviceId');
    await caseService.redeemFreeCase({ ownerId, deviceId });

    logger.info({ function: 'mmRedeemFreeCase', ownerId });

    return { redeemed: true };
  } catch (err) {
    logger.error({ function: 'mmRedeemFreeCase', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
