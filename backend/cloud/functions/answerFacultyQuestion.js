const caseService = require('../services/caseService');
const { requireNonEmptyString, requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Drafts a model answer to one of a case's own "likely faculty questions"
 * so the trainee has something concrete to rehearse against. Purely
 * additive: does not touch createCase/answerQuestion/finalizeCase/getCase,
 * and does not persist anything onto the case -- same "compute fresh, don't
 * persist" shape as mmFindReferences.
 */
Parse.Cloud.define('mmAnswerFacultyQuestion', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const caseId = requireNonEmptyString(params.caseId, 'caseId');
    const question = requireNonEmptyString(params.question, 'question');

    const result = await caseService.answerFacultyQuestion({ caseId, ownerId, question });

    logger.info({
      function: 'mmAnswerFacultyQuestion',
      caseId,
      latencyMs: Date.now() - startedAt,
    });

    return result;
  } catch (err) {
    logger.error({ function: 'mmAnswerFacultyQuestion', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
