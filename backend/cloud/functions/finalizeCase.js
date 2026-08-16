const caseService = require('../services/caseService');
const { requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmFinalizeCase', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const caseState = await caseService.finalizeCase({ caseId });

    logger.info({
      function: 'mmFinalizeCase',
      caseId,
      status: caseState.status,
      latencyMs: Date.now() - startedAt,
    });

    return caseService.formatFinalizedCase(caseState);
  } catch (err) {
    logger.error({ function: 'mmFinalizeCase', caseId: params.caseId, message: err.message });
    throw toParseError(err);
  }
});
