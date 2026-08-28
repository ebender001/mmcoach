/**
 * The only module that touches Parse.Object/Parse.Query directly for
 * MMCaseAICost -- one row per AI provider call, so cost is auditable
 * per-operation rather than only visible as a running total. See
 * `caseRepository.js#incrementAIUsage` for the MMCase-side running total
 * this also feeds (that field lives on MMCase, so only caseRepository
 * writes it -- this module never touches MMCase directly).
 *
 * Uses the master key for the same reason caseRepository does: only
 * Cloud Code should read/write this class. Per-object ACL below is
 * defense-in-depth, not the primary access control -- see
 * `services/caseService.js#getCaseAICost` for the real ownership check.
 */
const { estimateCostUSD } = require('../config/aiPricing');
const { CASE_CLASS_NAME } = require('./caseRepository');

const AI_COST_CLASS_NAME = 'MMCaseAICost';

function getAICostClass() {
  return Parse.Object.extend(AI_COST_CLASS_NAME);
}

function toClientJSON(parseObject) {
  return {
    objectId: parseObject.id,
    operation: parseObject.get('operation'),
    model: parseObject.get('model'),
    promptTokens: parseObject.get('promptTokens') || 0,
    completionTokens: parseObject.get('completionTokens') || 0,
    totalTokens: parseObject.get('totalTokens') || 0,
    costUSD: parseObject.get('costUSD'),
    latencyMs: parseObject.get('latencyMs') || null,
    createdAt: parseObject.createdAt,
  };
}

/**
 * Records one AI provider call against a case. `usage` is the raw OpenAI
 * `usage` object from `aiService.completeJSON`'s `meta` (may be null if
 * the provider didn't return one). Returns the computed `costUSD`
 * (`null` if `model` isn't in the pricing table) and `totalTokens` so the
 * caller can roll them into MMCase's running total.
 */
async function record({ caseId, ownerId, operation, model, usage, latencyMs }) {
  const AICost = getAICostClass();
  const row = new AICost();

  const promptTokens = (usage && usage.prompt_tokens) || 0;
  const completionTokens = (usage && usage.completion_tokens) || 0;
  const totalTokens = (usage && usage.total_tokens) || promptTokens + completionTokens;
  const costUSD = estimateCostUSD(model, usage);

  row.set('case', Parse.Object.extend(CASE_CLASS_NAME).createWithoutData(caseId));
  row.set('owner', Parse.User.createWithoutData(ownerId));
  row.set('operation', operation);
  row.set('model', model);
  row.set('promptTokens', promptTokens);
  row.set('completionTokens', completionTokens);
  row.set('totalTokens', totalTokens);
  row.set('costUSD', costUSD);
  row.set('latencyMs', latencyMs || null);

  const acl = new Parse.ACL();
  acl.setPublicReadAccess(false);
  acl.setPublicWriteAccess(false);
  acl.setReadAccess(ownerId, true);
  acl.setWriteAccess(ownerId, true);
  row.setACL(acl);

  await row.save(null, { useMasterKey: true });
  return { costUSD, totalTokens };
}

/** Every recorded AI-call row for a case, most recent first. */
async function listForCase(caseId) {
  const AICost = getAICostClass();
  const query = new Parse.Query(AICost);
  query.equalTo('case', Parse.Object.extend(CASE_CLASS_NAME).createWithoutData(caseId));
  query.descending('createdAt');
  const rows = await query.find({ useMasterKey: true });
  return rows.map(toClientJSON);
}

/**
 * Permanently removes every AI-cost row for a user -- part of account
 * deletion (see services/accountService.js). Queried by `owner` directly
 * rather than by first listing the user's case ids, since every row
 * already carries its own owner pointer (see `record()` above).
 */
async function deleteAllForOwner(ownerId) {
  const AICost = getAICostClass();
  const query = new Parse.Query(AICost);
  query.equalTo('owner', Parse.User.createWithoutData(ownerId));
  query.limit(1000);
  const rows = await query.find({ useMasterKey: true });
  if (rows.length > 0) {
    await Parse.Object.destroyAll(rows, { useMasterKey: true });
  }
}

/**
 * Every AI-cost row across every user, oldest first -- admin export only
 * (see functions/adminExportAICosts.js, services/adminService.js). Paginates
 * past Parse's 1000-row query cap with skip/limit rather than `query.each`,
 * since callers want a stable ascending-by-createdAt order for reporting.
 */
async function listAll({ sinceDate } = {}) {
  const AICost = getAICostClass();
  const pageSize = 1000;
  const rows = [];
  let skip = 0;

  for (;;) {
    const query = new Parse.Query(AICost);
    if (sinceDate) {
      query.greaterThanOrEqualTo('createdAt', sinceDate);
    }
    query.ascending('createdAt');
    query.limit(pageSize);
    query.skip(skip);
    // eslint-disable-next-line no-await-in-loop
    const page = await query.find({ useMasterKey: true });

    for (const row of page) {
      const caseObj = row.get('case');
      const ownerObj = row.get('owner');
      rows.push({
        objectId: row.id,
        caseId: caseObj ? caseObj.id : null,
        ownerId: ownerObj ? ownerObj.id : null,
        operation: row.get('operation'),
        model: row.get('model'),
        promptTokens: row.get('promptTokens') || 0,
        completionTokens: row.get('completionTokens') || 0,
        totalTokens: row.get('totalTokens') || 0,
        costUSD: row.get('costUSD'),
        latencyMs: row.get('latencyMs') || null,
        createdAt: row.createdAt,
      });
    }

    if (page.length < pageSize) break;
    skip += pageSize;
  }

  return rows;
}

module.exports = {
  record,
  listForCase,
  listAll,
  deleteAllForOwner,
  CLASS_NAME: AI_COST_CLASS_NAME,
};
