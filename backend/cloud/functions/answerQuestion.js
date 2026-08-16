const caseService = require('../services/caseService');
const { requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmAnswerQuestion', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const questionId = requireNonEmptyString(params.questionId, 'questionId');
    const answer = requireNonEmptyString(params.answer, 'answer');

    const caseState = await caseService.answerQuestion({ caseId, questionId, answer });

    logger.info({
      function: 'mmAnswerQuestion',
      caseId,
      status: caseState.status,
      latencyMs: Date.now() - startedAt,
    });

    return caseService.formatCaseSummary(caseState);
  } catch (err) {
    logger.error({ function: 'mmAnswerQuestion', caseId: params.caseId, message: err.message });
    throw toParseError(err);
  }
});
