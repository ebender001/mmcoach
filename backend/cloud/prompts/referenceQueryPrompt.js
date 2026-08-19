const { EDUCATOR_PERSONA } = require('./persona');

const REFERENCE_QUERY_PROMPT_VERSION = '1.0.0';

/**
 * Builds the prompt used to translate a discussion-prep reference topic
 * (plus the trainee-facing note on what it should help find) into one
 * well-formed PubMed search query -- rather than sending that free-text
 * topic straight to PubMed and relying entirely on its automatic term
 * mapping, which tends to under-target compound clinical phrases.
 */
function buildReferenceQueryPrompt({ topic, searchIntent }) {
  const system = `${EDUCATOR_PERSONA}

You translate a clinical discussion topic into a single, effective PubMed search query.

Use PubMed search syntax:
- MeSH headings with [mesh] where a clear, specific MeSH heading exists for a concept.
- Title/abstract keywords with [tiab] for concepts that don't map cleanly to one MeSH heading.
- Boolean AND to combine 2-4 concepts. Use OR only to group close synonyms within one concept (in parentheses), never to broaden across unrelated concepts.

Prefer terms and structure likely to surface reviews, guidelines, and comparative/observational studies over isolated case reports. Keep the query focused and precise -- a query so broad it returns thousands of unrelated results is not useful for exam prep, and a query so narrow (5+ ANDed concepts) it returns nothing is equally useless.

Respond only with a JSON object of this exact shape, no other text:
{ "query": "<the PubMed search query string>" }`;

  const user = `Discussion topic: ${topic}
What this search should help the trainee find: ${searchIntent || 'High-quality evidence directly relevant to this topic.'}

Write one PubMed search query for this.`;

  return { system, user };
}

module.exports = { REFERENCE_QUERY_PROMPT_VERSION, buildReferenceQueryPrompt };
