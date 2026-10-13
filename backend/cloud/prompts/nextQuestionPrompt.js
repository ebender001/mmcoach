const { EDUCATOR_PERSONA } = require('./persona');

const NEXT_QUESTION_PROMPT_VERSION = '1.1.0';

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

First, identify the specific procedure or clinical problem. Then consider what an experienced attending would need to know to discuss it well, including the technical and strategic choices that surgeons genuinely debate for that operation (for example, for carotid endarterectomy: patch versus primary closure, shunting, anesthetic type, patient sex and carotid size; for an aortic or bowel operation, the type of repair or anastomosis and why it was chosen). If the trainee has not said which of these key choices was made, that is usually the highest-value thing to ask about.

Not every M&M case involves a dramatic complication; it may be an expected complication, a near miss, a poor outcome after a technically routine operation, or a decision-making question. Do not assume there was a single "adverse event" or a clinical deterioration.

Consider the case sufficiently complete once you can reasonably:
1. reconstruct an understandable chronology,
2. identify what makes this case worth discussing (an event, complication, near miss, outcome, or management question),
3. understand the key decisions that were made, including the operation-specific technical choices and the reasoning behind them,
4. understand the actions taken and the response to treatment,
5. understand the final outcome,
6. anticipate a meaningful, case-specific M&M discussion.

Ask about what was done and decided, never about whether it was right. Do not keep asking questions simply because more detail could theoretically be gathered. Only ask about something if it would materially change understanding of the case.

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
