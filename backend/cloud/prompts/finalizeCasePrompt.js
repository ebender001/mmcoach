const { EDUCATOR_PERSONA } = require('./persona');

const FINALIZE_CASE_PROMPT_VERSION = '1.0.0';

/**
 * Builds the prompt used once information collection is complete, to
 * generate the presentation narrative and conference-preparation materials.
 */
function buildFinalizeCasePrompt({ extractedCase, conversation, originalNarrative }) {
  const qaSummary = conversation
    .filter((entry) => entry.answer)
    .map((entry) => `Q: ${entry.question}\nA: ${entry.answer}`)
    .join('\n\n');

  const system = `${EDUCATOR_PERSONA}

The trainee has finished gathering information for their M&M case. Produce the materials they need to prepare for the conference.

Generate:

1. "polishedNarrative": a chronological, concise narrative suitable for oral presentation at a surgical M&M conference. It should read like a trainee presenting the case out loud, not a discharge summary. Preserve important timing, relevant labs/imaging, interventions, and outcome. Clearly distinguish known facts from acknowledged uncertainty. Do not fabricate any detail that was not provided. Do not assign blame.

2. "discussionPreparation": an array of case-specific topics the trainee should be ready to discuss. Each item has "topic", "whyItMatters", and "prepareToDiscuss". Use neutral educational language -- do not declare that an error occurred. Draw from categories such as diagnostic reasoning, recognition of deterioration, timing of intervention, operative decision-making, technical considerations, alternative management strategies, postoperative management, escalation of care, adherence to evidence/guidelines, systems factors, and preventability, but only include what is actually relevant to this case.

3. "likelyFacultyQuestions": an array of 3 to 8 realistic questions a faculty member might ask at an academic M&M conference about this specific case. Avoid generic questions that could apply to any complication.

4. "referenceTopics": an array of topics where the trainee would benefit from supporting literature or guidelines, each with "topic" and "searchIntent". Do NOT fabricate citations, PubMed IDs, DOIs, authors, journals, or publication dates -- only describe what should be looked up later.

Respond only with a JSON object of the form:
{
  "polishedNarrative": "...",
  "discussionPreparation": [ { "topic": "...", "whyItMatters": "...", "prepareToDiscuss": "..." } ],
  "likelyFacultyQuestions": [ "..." ],
  "referenceTopics": [ { "topic": "...", "searchIntent": "..." } ]
}`;

  const user = `Original dictated narrative:
"""
${originalNarrative}
"""

Structured case information:
${JSON.stringify(extractedCase, null, 2)}

Follow-up questions and answers collected:
${qaSummary || '(none were needed)'}`;

  return { system, user };
}

module.exports = { FINALIZE_CASE_PROMPT_VERSION, buildFinalizeCasePrompt };
