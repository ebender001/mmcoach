const { EDUCATOR_PERSONA } = require('./persona');

const NEXT_QUESTION_PROMPT_VERSION = '1.0.0';

/**
 * Builds the prompt used to decide whether one more follow-up question is
 * needed, and if so, what the single highest-value question is.
 */
function buildNextQuestionPrompt({ extractedCase, conversation }) {
  const askedSoFar = conversation
    .map((entry, idx) => {
      const answerLine = entry.answer ? `   A: ${entry.answer}` : '   (not yet answered)';
      return `${idx + 1}. Q: ${entry.question}\n${answerLine}`;
    })
    .join('\n');

  const system = `${EDUCATOR_PERSONA}

You are deciding whether the trainee needs to answer one more follow-up question before this case is ready to become an M&M presentation.

Consider the case sufficiently complete once you can reasonably:
1. reconstruct an understandable chronology,
2. identify the major adverse event,
3. understand the patient's clinical deterioration,
4. understand the actions taken,
5. identify the major decision points,
6. understand the response to treatment,
7. understand the final outcome,
8. anticipate a meaningful M&M discussion.

Do not keep asking questions simply because more detail could theoretically be gathered. Only ask about something if it would materially change understanding of the case.

If another question is needed, choose the single highest-value missing item. Never re-ask about information already present in the structured case or the conversation below. Keep the question concise, specific to this case, and phrased the way a thoughtful attending would ask it -- never a generic checklist item like "Were labs obtained?" when detailed labs are already provided.

Respond only with a JSON object of one of these two forms:
{ "needsQuestion": false, "question": null }
or
{ "needsQuestion": true, "question": { "text": "...", "category": "...", "reason": "..." } }

"category" should be a short lowercase label such as "timing", "laboratory", "vital signs", "imaging", "intervention", "outcome", or "consultation" (or another concise label that fits). "reason" should briefly explain why this question matters for THIS case.`;

  const user = `Current structured case:
${JSON.stringify(extractedCase, null, 2)}

Questions already asked in this conversation:
${askedSoFar || '(none yet)'}`;

  return { system, user };
}

module.exports = { NEXT_QUESTION_PROMPT_VERSION, buildNextQuestionPrompt };
