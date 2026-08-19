const pubmedService = require('../services/pubmedService');
const referenceQueryBuilder = require('../ai/referenceQueryBuilder');
const caseService = require('../services/caseService');
const { requireNonEmptyString, requireAuthenticatedUser } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

function optionalString(value) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : '';
}

/**
 * `caseId` is optional (defensive/backward-compatible) but the iOS client
 * always sends it -- when present it's used two ways: to verify the
 * caller owns that case (via caseService.getCase, same NotFoundError
 * either way as every other case-scoped function) before recording
 * anything against it, and to roll the AI query-building call's cost
 * into that case's running AI-cost total (see backend README "AI cost
 * tracking") so this doesn't become an untracked AI call path.
 */
Parse.Cloud.define('mmFindReferences', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const topic = requireNonEmptyString(params.topic, 'topic');
    const searchIntent = optionalString(params.searchIntent);
    const caseId = optionalString(params.caseId);

    if (caseId) {
      await caseService.getCase({ caseId, ownerId });
    }

    const queryResult = await referenceQueryBuilder.buildQuery({ topic, searchIntent });
    if (caseId) {
      await caseService.recordAIUsage({
        caseId,
        ownerId,
        operation: 'buildReferenceQuery',
        meta: queryResult.meta,
      });
    }

    let results = await pubmedService.findReferences({ query: queryResult.query, maxResults: 5 });
    if (results.length === 0 && queryResult.query !== topic) {
      // The AI-crafted query can occasionally over-constrain (too many
      // ANDed concepts) and return nothing PubMed would otherwise have --
      // fall back to the plain topic rather than showing "no results".
      results = await pubmedService.findReferences({ query: topic, maxResults: 5 });
    }

    logger.info({
      function: 'mmFindReferences',
      resultCount: results.length,
      latencyMs: Date.now() - startedAt,
    });

    return { topic, results };
  } catch (err) {
    logger.error({ function: 'mmFindReferences', message: err.message });
    throw toParseError(err);
  }
}, { requireUser: true });
