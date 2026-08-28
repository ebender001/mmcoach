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
 * always sends it -- when present it's used three ways: to verify the
 * caller owns that case (same NotFoundError either way as every other
 * case-scoped function) before recording anything against it, to serve a
 * previously-looked-up topic straight from that case's cache with no AI
 * or PubMed call at all, and -- on a cache miss -- to roll the AI
 * query-building call's cost into that case's running AI-cost total (see
 * backend README "AI cost tracking") and cache the result for next time.
 */
Parse.Cloud.define('mmFindReferences', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const ownerId = requireAuthenticatedUser(request);
    const topic = requireNonEmptyString(params.topic, 'topic');
    const searchIntent = optionalString(params.searchIntent);
    const caseId = optionalString(params.caseId);

    let existingLookups = null;
    if (caseId) {
      const { caseState, cached } = await caseService.getCachedReferenceLookup({ caseId, ownerId, topic });
      if (cached) {
        logger.info({ function: 'mmFindReferences', caseId, cacheHit: true, resultCount: cached.results.length });
        return { topic, results: cached.results };
      }
      existingLookups = caseState.referenceLookups;
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

    if (caseId) {
      await caseService.cacheReferenceLookup({ caseId, existingLookups, topic, query: queryResult.query, results });
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
