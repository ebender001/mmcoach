const dictationCorrector = require('../ai/dictationCorrector');
const { requireNonEmptyString } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

Parse.Cloud.define('mmCorrectDictation', async (request) => {
  const startedAt = Date.now();
  const params = request.params || {};
  try {
    const newSegment = requireNonEmptyString(params.newSegment, 'newSegment');
    const priorNarrative = typeof params.priorNarrative === 'string' ? params.priorNarrative.trim() : '';

    const result = await dictationCorrector.correctSegment({ priorNarrative, newSegment });

    logger.info({
      function: 'mmCorrectDictation',
      changeCount: result.changes.length,
      latencyMs: Date.now() - startedAt,
    });

    return { correctedSegment: result.correctedSegment, changes: result.changes };
  } catch (err) {
    logger.error({ function: 'mmCorrectDictation', message: err.message });
    throw toParseError(err);
  }
});
