const { EDUCATOR_PERSONA } = require('./persona');

const FACULTY_QUESTION_ANSWER_PROMPT_VERSION = '1.0.0';

/**
 * Builds the prompt used to draft a model answer to one of the case's own
 * "likely faculty questions" -- grounded only in what the trainee actually
 * provided, so they have something concrete to rehearse against rather than
 * facing that question cold at the conference.
 */
function buildFacultyQuestionAnswerPrompt({ extractedCase, conversation, polishedNarrative, question }) {
  const qaSummary = conversation
    .filter((entry) => entry.answer)
    .map((entry) => `Q: ${entry.question}\nA: ${entry.answer}`)
    .join('\n\n');

  const system = `${EDUCATOR_PERSONA}

The trainee is rehearsing for their M&M presentation. A faculty member may ask them the question below. Draft the answer the trainee should be prepared to give -- reason through the clinical decision-making using only the case details provided below, rather than just restating facts. Where the case doesn't provide enough information to fully answer, say so plainly rather than inventing details, and note what a thoughtful trainee would acknowledge as a limitation or uncertainty.

Keep the answer concise enough to say out loud in under a minute (roughly 3-6 sentences).

Respond only with a JSON object of this exact shape, no other text:
{ "answer": "<the model answer>" }`;

  const user = `Polished case narrative:
"""
${polishedNarrative || '(not yet available)'}
"""

Structured case information:
${JSON.stringify(extractedCase, null, 2)}

Follow-up questions and answers collected during the interview:
${qaSummary || '(none were needed)'}

Faculty question to answer:
${question}`;

  return { system, user };
}

module.exports = { FACULTY_QUESTION_ANSWER_PROMPT_VERSION, buildFacultyQuestionAnswerPrompt };
