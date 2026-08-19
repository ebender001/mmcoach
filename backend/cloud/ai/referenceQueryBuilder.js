/**
 * Responsible for turning a reference topic + search intent into a
 * well-formed PubMed query. Does not touch PubMed itself (see
 * services/pubmedService.js) -- this only produces the query string.
 */
const aiService = require('../services/aiService');
const { REFERENCE_QUERY_PROMPT_VERSION, buildReferenceQueryPrompt } = require('../prompts/referenceQueryPrompt');
const { validateReferenceQueryResponse } = require('../schemas/aiResponseSchemas');

async function buildQuery({ topic, searchIntent }) {
  const { system, user } = buildReferenceQueryPrompt({ topic, searchIntent });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    temperature: 0.2,
    operation: 'buildReferenceQuery',
  });
  const result = validateReferenceQueryResponse(data);
  return { ...result, meta, promptVersion: REFERENCE_QUERY_PROMPT_VERSION };
}

module.exports = { buildQuery };
