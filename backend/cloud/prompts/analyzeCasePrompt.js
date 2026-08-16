const { EDUCATOR_PERSONA } = require('./persona');
const { EXTRACTED_CASE_FIELDS } = require('../schemas/extractedCaseSchema');

const ANALYZE_CASE_PROMPT_VERSION = '1.0.0';

const FIELD_GUIDANCE = `Possible extractedCase fields (use only the ones relevant to this case; omit fields you have no information about; never invent values):
${EXTRACTED_CASE_FIELDS.map((field) => `- ${field}`).join('\n')}

You may use other field names if something important doesn't fit the list above. Include an "uncertainties" field: a short array of strings describing clinically important facts that are still unknown or unclear. Do not pad it with trivial items.`;

/**
 * Builds the prompt used the first time a case is created, extracting
 * structured facts from the trainee's raw dictated narrative.
 */
function buildInitialAnalysisPrompt(narrative) {
  const system = `${EDUCATOR_PERSONA}

You are reviewing a trainee's initial dictated narrative of a surgical M&M case. Extract the clinically meaningful information into a structured object, and note what important information is still unknown.

${FIELD_GUIDANCE}

Respond only with a JSON object of the form:
{
  "extractedCase": { ... }
}

Do not include any keys other than "extractedCase". Do not fabricate details that were not stated or clearly implied by the narrative.`;

  const user = `Trainee's dictated narrative:
"""
${narrative}
"""`;

  return { system, user };
}

/**
 * Builds the prompt used to merge a trainee's follow-up answer into the
 * existing structured case, rather than re-extracting from scratch.
 */
function buildIncorporateAnswerPrompt({ extractedCase, conversation, newEntry }) {
  const priorQA = conversation
    .filter((entry) => entry.answer)
    .map((entry) => `Q: ${entry.question}\nA: ${entry.answer}`)
    .join('\n\n');

  const system = `${EDUCATOR_PERSONA}

You previously extracted a structured summary of a trainee's M&M case. The trainee has just answered a follow-up question. Update the structured case with the new information.

${FIELD_GUIDANCE}

Merge the new answer into the existing structured case rather than starting over. Preserve previously captured information unless the new answer corrects it. Remove an item from "uncertainties" once it has been resolved.

Respond only with a JSON object of the form:
{
  "extractedCase": { ... }
}`;

  const user = `Current structured case:
${JSON.stringify(extractedCase, null, 2)}

Conversation so far:
${priorQA || '(no prior questions answered yet)'}

Most recent question and answer to incorporate:
Q: ${newEntry.question}
A: ${newEntry.answer}`;

  return { system, user };
}

module.exports = {
  ANALYZE_CASE_PROMPT_VERSION,
  buildInitialAnalysisPrompt,
  buildIncorporateAnswerPrompt,
};
