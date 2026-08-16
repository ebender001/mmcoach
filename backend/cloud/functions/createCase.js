const caseService = require('../services/caseService');
const { requireMeaningfulNarrative } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmCreateCase', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const narrative = requireMeaningfulNarrative(params.narrative);
    const caseState = await caseService.createCase({ narrative });

    logger.info({
      function: 'mmCreateCase',
      caseId: caseState.objectId,
      status: caseState.status,
      latencyMs: Date.now() - startedAt,
    });

    return caseService.formatCaseSummary(caseState);
  } catch (err) {
    logger.error({ function: 'mmCreateCase', message: err.message });
    throw toParseError(err);
  }
});
