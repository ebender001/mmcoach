const caseService = require('../services/caseService');
const { requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmGetCase', async (request) => {
  const params = request.params || {};
  try {
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const caseState = await caseService.getCase({ caseId });

    logger.info({ function: 'mmGetCase', caseId, status: caseState.status });

    return caseService.formatFullCase(caseState);
  } catch (err) {
    logger.error({ function: 'mmGetCase', caseId: params.caseId, message: err.message });
    throw toParseError(err);
  }
});
