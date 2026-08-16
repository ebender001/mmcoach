/**
 * Owns the shape and (eventually) retrieval of supporting literature.
 *
 * MVP scope: convert AI-identified reference *topics* into pending
 * reference entries. No citations are fabricated -- citation stays null
 * and verified stays false until a real retrieval/verification feature
 * (e.g. PubMed lookup) is implemented.
 */

function buildPendingReferences(referenceTopics) {
  if (!Array.isArray(referenceTopics)) {
    return [];
  }
  return referenceTopics.map((ref) => ({
    topic: ref.topic,
    searchIntent: ref.searchIntent || '',
    citation: null,
    verified: false,
  }));
}

/**
 * Placeholder for future literature retrieval & verification (e.g. a
 * PubMed/guideline search). Not implemented in the MVP -- references are
 * returned unchanged. Kept here so this capability has an obvious home.
 */
async function retrieveAndVerifyReferences(references) {
  return references;
}

module.exports = { buildPendingReferences, retrieveAndVerifyReferences };
