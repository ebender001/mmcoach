/**
 * Admin/reporting concerns that cut across every user's data -- distinct
 * from caseService, which only ever acts within one owner's cases. Gated
 * by MMCOACH_ADMIN_SECRET (see utils/validation.js#requireAdminSecret) at
 * the Cloud Function boundary, not by Parse.User ownership, since there's
 * no per-user scope to check for a cross-user export.
 */
const aiCostRepository = require('../repositories/aiCostRepository');

/**
 * Every MMCaseAICost row (optionally since `sinceDate`), plus a summary
 * total. `costUSD` is `null` on rows whose model isn't in the pricing
 * table (see aiPricing.js) -- those are excluded from `totalCostUSD` but
 * still counted in `rowCount`/`totalTokens`.
 */
async function exportAICosts({ sinceDate } = {}) {
  const rows = await aiCostRepository.listAll({ sinceDate });

  const summary = rows.reduce(
    (acc, row) => {
      acc.rowCount += 1;
      acc.totalTokens += row.totalTokens || 0;
      if (typeof row.costUSD === 'number') {
        acc.totalCostUSD += row.costUSD;
      }
      return acc;
    },
    { rowCount: 0, totalTokens: 0, totalCostUSD: 0 }
  );

  return { rows, summary };
}

module.exports = { exportAICosts };
