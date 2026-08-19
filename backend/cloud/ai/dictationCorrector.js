/**
 * Cleans up a freshly-dictated narrative segment before the trainee sees
 * it, correcting speech-recognition errors that swap a medical term for an
 * unrelated, correctly-spelled everyday word (a class of error on-device
 * text/phonetic matching can't recover, since no trace of the original word
 * is left to work from). Does NOT touch prior narrative -- see
 * prompts/correctDictationPrompt.js.
 */
const aiService = require('../services/aiService');
const {
  CORRECT_DICTATION_PROMPT_VERSION,
  buildCorrectDictationPrompt,
} = require('../prompts/correctDictationPrompt');
const { validateCorrectDictationResponse } = require('../schemas/aiResponseSchemas');

async function correctSegment({ priorNarrative, newSegment }) {
  const { system, user } = buildCorrectDictationPrompt({ priorNarrative, newSegment });
  const { data, meta } = await aiService.completeJSON({
    system,
    user,
    operation: 'correctDictationSegment',
  });
  const result = validateCorrectDictationResponse(data);
  return { ...result, meta, promptVersion: CORRECT_DICTATION_PROMPT_VERSION };
}

module.exports = { correctSegment };
