const caseService = require('../services/caseService');
const { requireNonEmptyString, requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmGetCaseAICost', async (request) => {
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const result = await caseService.getCaseAICost({ caseId, ownerId });

    logger.info({ function: 'mmGetCaseAICost', caseId, totalCostUSD: result.totalCostUSD });

    return result;
  } catch (err) {
    logger.error({ function: 'mmGetCaseAICost', caseId: params.caseId, message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
