/**
 * The only module that touches Parse.Object / Parse.Query directly for
 * MMCase. Everything else works with plain JSON case objects.
 *
 * Uses the master key because Cloud Code is the only path allowed to
 * read/write MMCase -- Class-Level Permissions on MMCase deny direct
 * client REST/SDK access (see README "Back4App setup"). Master key use
 * means Parse's own ACL enforcement never runs here, so per-user
 * ownership is enforced explicitly in `services/caseService.js` (it
 * compares `request.user.id` against the `ownerId` this module returns)
 * rather than relied upon implicitly. The ACL this module still sets on
 * every case is defense-in-depth for if CLP is ever loosened later, not
 * the primary access-control mechanism.
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
  const owner = parseObject.get('owner');
  return {
    objectId: parseObject.id,
    ownerId: owner ? owner.id : null,
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

/**
 * `record` must include `ownerId` -- the authenticated caller's user id,
 * resolved by the Cloud Function from `request.user` (see
 * `utils/validation.js#requireAuthenticatedUser`). Never accept an
 * `ownerId` sourced from client params.
 */
async function create({ ownerId, ...record }) {
  const MMCase = getMMCaseClass();
  const parseObject = new MMCase();
  applyFields(parseObject, record);

  const owner = Parse.User.createWithoutData(ownerId);
  parseObject.set('owner', owner);

  const acl = new Parse.ACL();
  acl.setPublicReadAccess(false);
  acl.setPublicWriteAccess(false);
  acl.setReadAccess(ownerId, true);
  acl.setWriteAccess(ownerId, true);
  parseObject.setACL(acl);

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
