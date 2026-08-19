const caseService = require('../services/caseService');
const { requireNonEmptyString, requireMeaningfulNarrative, requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmUpdatePolishedNarrative', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const polishedNarrative = requireMeaningfulNarrative(params.polishedNarrative, { fieldName: 'polishedNarrative' });

    const caseState = await caseService.updatePolishedNarrative({ caseId, ownerId, polishedNarrative });

    logger.info({
      function: 'mmUpdatePolishedNarrative',
      caseId,
      latencyMs: Date.now() - startedAt,
    });

    return caseService.formatFinalizedCase(caseState);
  } catch (err) {
    logger.error({ function: 'mmUpdatePolishedNarrative', caseId: params.caseId, message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
