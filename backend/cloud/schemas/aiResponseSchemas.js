/**
 * Validates and sanitizes JSON returned by the AI provider before it is
 * ever stored or returned to a client. AI output is never trusted as-is.
 */
const { AIResponseError } = require('../utils/errors');
const { sanitizeExtractedCase } = require('./extractedCaseSchema');

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function validateAnalyzeCaseResponse(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AIResponseError('Case analysis response was not a JSON object.');
  }
  if (typeof data.extractedCase !== 'object' || data.extractedCase === null || Array.isArray(data.extractedCase)) {
    throw new AIResponseError('Case analysis response is missing a valid extractedCase object.');
  }
  return { extractedCase: sanitizeExtractedCase(data.extractedCase) };
}

function validateQuestionShape(question, context) {
  if (!question || typeof question !== 'object' || Array.isArray(question)) {
    throw new AIResponseError(`${context} is missing a valid question object.`);
  }
  if (!isNonEmptyString(question.text)) {
    throw new AIResponseError(`${context} question is missing "text".`);
  }
  if (!isNonEmptyString(question.category)) {
    throw new AIResponseError(`${context} question is missing "category".`);
  }
  if (!isNonEmptyString(question.reason)) {
    throw new AIResponseError(`${context} question is missing "reason".`);
  }
  return {
    text: question.text.trim(),
    category: question.category.trim(),
    reason: question.reason.trim(),
  };
}

function validateNextQuestionResponse(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AIResponseError('Next-question response was not a JSON object.');
  }
  if (typeof data.needsQuestion !== 'boolean') {
    throw new AIResponseError('Next-question response is missing a "needsQuestion" boolean.');
  }
  if (!data.needsQuestion) {
    return { needsQuestion: false, question: null };
  }
  return { needsQuestion: true, question: validateQuestionShape(data.question, 'Next-question response') };
}

function validateFinalizeCaseResponse(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AIResponseError('Finalize response was not a JSON object.');
  }
  if (!isNonEmptyString(data.polishedNarrative)) {
    throw new AIResponseError('Finalize response is missing "polishedNarrative".');
  }

  const discussionPreparation = Array.isArray(data.discussionPreparation)
    ? data.discussionPreparation
        .filter((topic) => topic && typeof topic === 'object')
        .map((topic) => ({
          topic: isNonEmptyString(topic.topic) ? topic.topic.trim() : 'Discussion topic',
          whyItMatters: isNonEmptyString(topic.whyItMatters) ? topic.whyItMatters.trim() : '',
          prepareToDiscuss: isNonEmptyString(topic.prepareToDiscuss) ? topic.prepareToDiscuss.trim() : '',
        }))
    : [];

  const likelyFacultyQuestions = Array.isArray(data.likelyFacultyQuestions)
    ? data.likelyFacultyQuestions.filter(isNonEmptyString).map((q) => q.trim())
    : [];

  const referenceTopics = Array.isArray(data.referenceTopics)
    ? data.referenceTopics
        .filter((ref) => ref && typeof ref === 'object' && isNonEmptyString(ref.topic))
        .map((ref) => ({
          topic: ref.topic.trim(),
          searchIntent: isNonEmptyString(ref.searchIntent) ? ref.searchIntent.trim() : '',
        }))
    : [];

  if (discussionPreparation.length === 0) {
    throw new AIResponseError('Finalize response did not include any discussion preparation topics.');
  }
  if (likelyFacultyQuestions.length === 0) {
    throw new AIResponseError('Finalize response did not include any likely faculty questions.');
  }

  return {
    polishedNarrative: data.polishedNarrative.trim(),
    discussionPreparation,
    likelyFacultyQuestions,
    referenceTopics,
  };
}

function validateCorrectDictationResponse(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AIResponseError('Correct-dictation response was not a JSON object.');
  }
  if (!isNonEmptyString(data.correctedSegment)) {
    throw new AIResponseError('Correct-dictation response is missing "correctedSegment".');
  }

  const changes = Array.isArray(data.changes)
    ? data.changes
        .filter(
          (change) =>
            change &&
            typeof change === 'object' &&
            isNonEmptyString(change.original) &&
            isNonEmptyString(change.corrected)
        )
        .map((change) => ({ original: change.original.trim(), corrected: change.corrected.trim() }))
    : [];

  return { correctedSegment: data.correctedSegment.trim(), changes };
}

module.exports = {
  validateAnalyzeCaseResponse,
  validateNextQuestionResponse,
  validateFinalizeCaseResponse,
  validateCorrectDictationResponse,
};
