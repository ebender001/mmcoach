/**
 * Responsible for drafting a model answer to one of a case's own
 * "likely faculty questions". Does not touch caseRepository -- caseService
 * is the one that fetches/owns the case and records AI usage.
 */
const aiService = require('../services/aiService');
const { FACULTY_QUESTION_ANSWER_PROMPT_VERSION, buildFacultyQuestionAnswerPrompt } = require('../prompts/facultyQuestionAnswerPrompt');
const { validateFacultyQuestionAnswerResponse } = require('../schemas/aiResponseSchemas');

async function answerQuestion({ extractedCase, conversation, polishedNarrative, question, caseId }) {
  const { system, user } = buildFacultyQuestionAnswerPrompt({ extractedCase, conversation, polishedNarrative, question });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    temperature: 0.3,
    operation: 'answerFacultyQuestion',
    caseId,
  });
  const result = validateFacultyQuestionAnswerResponse(data);
  return { ...result, meta, promptVersion: FACULTY_QUESTION_ANSWER_PROMPT_VERSION };
}

module.exports = { answerQuestion };
