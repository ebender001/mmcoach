/**
 * Responsible for generating the polished presentation narrative,
 * discussion-preparation topics, likely faculty questions, and pending
 * reference topics once information collection is complete.
 */
const aiService = require('../services/aiService');
const { FINALIZE_CASE_PROMPT_VERSION, buildFinalizeCasePrompt } = require('../prompts/finalizeCasePrompt');
const { validateFinalizeCaseResponse } = require('../schemas/aiResponseSchemas');
const referenceService = require('../services/referenceService');

async function finalizeCase({ extractedCase, conversation, originalNarrative, caseId }) {
  const { system, user } = buildFinalizeCasePrompt({ extractedCase, conversation, originalNarrative });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    temperature: 0.4,
    operation: 'finalizeCase',
    caseId,
  });
  const result = validateFinalizeCaseResponse(data);
  const references = referenceService.buildPendingReferences(result.referenceTopics);

  return {
    polishedNarrative: result.polishedNarrative,
    discussionPreparation: result.discussionPreparation,
    likelyFacultyQuestions: result.likelyFacultyQuestions,
    references,
    meta,
    promptVersion: FINALIZE_CASE_PROMPT_VERSION,
  };
}

module.exports = { finalizeCase };
