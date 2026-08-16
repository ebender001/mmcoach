/**
 * Responsible for deciding whether another follow-up question is needed
 * and, if so, authoring the single highest-value question. Does not touch
 * extractedCase directly -- it only reads it.
 */
const aiService = require('../services/aiService');
const { NEXT_QUESTION_PROMPT_VERSION, buildNextQuestionPrompt } = require('../prompts/nextQuestionPrompt');
const { validateNextQuestionResponse } = require('../schemas/aiResponseSchemas');

async function generateNextQuestion({ extractedCase, conversation, caseId }) {
  const { system, user } = buildNextQuestionPrompt({ extractedCase, conversation });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    operation: 'generateNextQuestion',
    caseId,
  });
  const result = validateNextQuestionResponse(data);
  return { ...result, meta, promptVersion: NEXT_QUESTION_PROMPT_VERSION };
}

module.exports = { generateNextQuestion };
