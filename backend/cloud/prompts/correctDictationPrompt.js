const CORRECT_DICTATION_PROMPT_VERSION = '1.0.0';

/**
 * Builds the prompt used to clean up one freshly-dictated segment of an M&M
 * case narrative. Only the new segment is corrected -- prior narrative is
 * passed along purely as context, not something the model should re-edit,
 * so already-reviewed text never gets silently rewritten a second time.
 */
function buildCorrectDictationPrompt({ priorNarrative, newSegment }) {
  const system = `You are cleaning up one segment of speech-to-text output from a surgical trainee dictating an M&M case narrative.

On-device and server speech recognition sometimes mishears a medical term as an unrelated, correctly-spelled everyday word, or splits it into multiple wrong words. For example: "saphenous" heard as "sadness" or "savageness" or split into "Saffin his"; "mammary" heard as "memory"; "coronary" heard as "corner". Fix ONLY clear errors of this kind, where you are reasonably confident what clinical term was actually intended given the surrounding context.

Do not rephrase, rewrite, summarize, reorder, or otherwise "improve" the trainee's wording. Preserve their sentence structure and level of detail exactly, including disfluencies or self-corrections that are plausibly what was actually said (e.g. "chest tube drain drainage") rather than a mishearing -- only touch words you believe recognition actually got wrong. If a word or phrase is ambiguous and you are not reasonably confident what was actually said, leave it unchanged rather than guessing.

Respond only with a JSON object of the form:
{
  "correctedSegment": "...",
  "changes": [{ "original": "...", "corrected": "..." }]
}

"correctedSegment" must be the full new segment with only your fixes applied -- do not omit or truncate any part of it. "changes" should list only the specific words/phrases you changed, in the order they appear; use an empty array if you made no changes.`;

  const contextBlock = priorNarrative
    ? `Narrative so far, for context only -- do not repeat, re-edit, or reference this part in your output:\n"""\n${priorNarrative}\n"""\n\n`
    : '';

  const user = `${contextBlock}New dictated segment to correct:
"""
${newSegment}
"""`;

  return { system, user };
}

module.exports = { CORRECT_DICTATION_PROMPT_VERSION, buildCorrectDictationPrompt };
