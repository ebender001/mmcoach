/**
 * The only module that touches Parse.Object / Parse.Query directly for
 * MMCase. Everything else works with plain JSON case objects.
 *
 * Uses the master key because MMCase has no per-user ownership in the MVP
 * (there is no Parse User auth yet). Class-Level Permissions on MMCase
 * should deny direct client REST access so only Cloud Code can read/write
 * it -- see README "Back4App setup".
 */
const CASE_CLASS_NAME = 'MMCase';

function getMMCaseClass() {
  return Parse.Object.extend(CASE_CLASS_NAME);
}

function applyFields(parseObject, fields) {
  Object.entries(fields).forEach(([key, value]) => {
    parseObject.set(key, value === undefined ? null : value);
  });
}

function toClientJSON(parseObject) {
  return {
    objectId: parseObject.id,
    status: parseObject.get('status'),
    originalNarrative: parseObject.get('originalNarrative') || '',
    extractedCase: parseObject.get('extractedCase') || {},
    conversation: parseObject.get('conversation') || [],
    currentQuestion: parseObject.get('currentQuestion') || null,
    polishedNarrative: parseObject.get('polishedNarrative') || null,
    discussionPreparation: parseObject.get('discussionPreparation') || [],
    likelyFacultyQuestions: parseObject.get('likelyFacultyQuestions') || [],
    references: parseObject.get('references') || [],
    promptVersion: parseObject.get('promptVersion') || {},
    aiModel: parseObject.get('aiModel') || null,
    createdAt: parseObject.createdAt,
    updatedAt: parseObject.updatedAt,
  };
}

async function create(record) {
  const MMCase = getMMCaseClass();
  const parseObject = new MMCase();
  applyFields(parseObject, record);
  await parseObject.save(null, { useMasterKey: true });
  return toClientJSON(parseObject);
}

/**
 * Returns the client-facing case JSON, or null if the id doesn't resolve
 * to an existing MMCase (including malformed ids) -- callers treat both
 * the same way: case not found.
 */
async function getById(caseId) {
  const MMCase = getMMCaseClass();
  const query = new Parse.Query(MMCase);
  try {
    const parseObject = await query.get(caseId, { useMasterKey: true });
    return toClientJSON(parseObject);
  } catch (err) {
    return null;
  }
}

async function update(caseId, patch) {
  const MMCase = getMMCaseClass();
  const query = new Parse.Query(MMCase);
  const parseObject = await query.get(caseId, { useMasterKey: true });
  applyFields(parseObject, patch);
  await parseObject.save(null, { useMasterKey: true });
  return toClientJSON(parseObject);
}

module.exports = { create, getById, update, toClientJSON, CASE_CLASS_NAME };
