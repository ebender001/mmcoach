const { EDUCATOR_PERSONA } = require('./persona');

const FINALIZE_CASE_PROMPT_VERSION = '1.2.1';

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

Before writing anything, think like an attending who knows this operation or condition well. Identify the specific procedure or clinical problem, then identify the decision points and controversies that surgeons genuinely debate for it: technique choices (for example patch versus primary closure, shunting, anesthetic or access approach, type of repair or reconstruction), patient factors that change the approach (sex, age, anatomy, comorbidity, urgency), timing of intervention, and where current evidence or guidelines support more than one reasonable approach. Record this in "caseFraming" first. It is used only to organize your thinking and is not shown to the trainee.

Knowledge versus facts: use established surgical knowledge and standard practice to decide WHAT is worth discussing, but never to state what happened to THIS patient. Facts about the patient and the operation must come only from the trainee. If a key decision point was not described (for example, how the arteriotomy was closed), do not assume an answer: frame the topic around that decision and, where useful, say that the trainee should be ready to explain what was done and why.

Specificity: every discussion topic and faculty question must hinge on a concrete decision, technique, or controversy particular to this procedure and this patient. Do not include any item that would fit almost any surgical case (for example "communication", "early recognition of complications", "systems factors") unless this case clearly raised it. Prefer fewer, sharper items over a broad generic list.

Generate:

1. "polishedNarrative": a chronological, concise narrative suitable for oral presentation at a surgical M&M conference. It should read like a trainee presenting the case out loud, not a discharge summary. Preserve important timing, relevant labs/imaging, interventions, and outcome. Clearly distinguish known facts from acknowledged uncertainty. Do not fabricate any detail that was not provided. Do not assign blame.

2. "discussionPreparation": an array of case-specific topics the trainee should be ready to discuss. Each item has "topic", "whyItMatters", and "prepareToDiscuss". Use neutral educational language -- do not declare that an error occurred. Order them by how likely they are to be probed at conference. Where relevant, include the operation-specific technical or strategic choices and the evidence behind them. You may also draw from categories such as diagnostic reasoning, recognition of deterioration, timing of intervention, operative decision-making, technical considerations, alternative management strategies, postoperative management, escalation of care, adherence to evidence/guidelines, systems factors, and preventability, but only include what is actually relevant to this case.

3. "likelyFacultyQuestions": an array of 3 to 8 realistic questions a faculty member might ask at an academic M&M conference about this specific case. Avoid generic questions that could apply to any complication or any operation. Include the pointed technical and decision-making questions a senior faculty member would ask about this specific procedure.

4. "referenceTopics": an array of topics where the trainee would benefit from supporting literature or guidelines, each with "topic" and "searchIntent". Do NOT fabricate citations, PubMed IDs, DOIs, authors, journals, or publication dates -- only describe what should be looked up later.

Respond only with a JSON object of the form:
{
  "caseFraming": "two to four sentences: the procedure or problem and its key decision points and controversies",
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
