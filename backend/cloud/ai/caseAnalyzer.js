/**
 * Responsible for interpreting the trainee's narrative and maintaining the
 * structured extractedCase as new answers arrive. Does NOT decide whether
 * another question is needed (see ai/questionGenerator.js) and does NOT
 * generate the final presentation (see ai/finalizer.js).
 */
const aiService = require('../services/aiService');
const {
  ANALYZE_CASE_PROMPT_VERSION,
  buildInitialAnalysisPrompt,
  buildIncorporateAnswerPrompt,
} = require('../prompts/analyzeCasePrompt');
const { validateAnalyzeCaseResponse } = require('../schemas/aiResponseSchemas');

async function analyzeInitialNarrative({ narrative, caseId }) {
  const { system, user } = buildInitialAnalysisPrompt(narrative);
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    operation: 'analyzeInitialNarrative',
    caseId,
  });
  const result = validateAnalyzeCaseResponse(data);
  return { ...result, meta, promptVersion: ANALYZE_CASE_PROMPT_VERSION };
}

async function incorporateAnswer({ extractedCase, conversation, newEntry, caseId }) {
  const { system, user } = buildIncorporateAnswerPrompt({ extractedCase, conversation, newEntry });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    operation: 'incorporateAnswer',
    caseId,
  });
  const result = validateAnalyzeCaseResponse(data);
  return { ...result, meta, promptVersion: ANALYZE_CASE_PROMPT_VERSION };
}

module.exports = { analyzeInitialNarrative, incorporateAnswer };
