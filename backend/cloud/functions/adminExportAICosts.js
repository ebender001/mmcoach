const adminService = require('../services/adminService');
const { requireAdminSecret } = require('../utils/validation');
const { toParseError } = require('../utils/errors');
const logger = require('../utils/logger');

/**
 * Cross-user AI-cost export for offline reporting (see the gitignored
 * admin-tools/aiCostReport script at the repo root -- this function is its
 * only data source). Gated by MMCOACH_ADMIN_SECRET rather than
 * `{ requireUser: true }`: there is no legitimate per-user session for a
 * solo-developer cost report, and MMCaseAICost's CLP already blocks every
 * other path to this data (see README "Back4App setup").
 */
Parse.Cloud.define('mmAdminExportAICosts', async (request) => {
  const params = request.params || {};
  try {
    requireAdminSecret(request);

    const sinceDays = params.sinceDays ? Number(params.sinceDays) : null;
    const sinceDate =
      sinceDays && sinceDays > 0 ? new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000) : undefined;

    const result = await adminService.exportAICosts({ sinceDate });

    logger.info({
      function: 'mmAdminExportAICosts',
      rowCount: result.summary.rowCount,
      totalCostUSD: result.summary.totalCostUSD,
    });

    return result;
  } catch (err) {
    logger.error({ function: 'mmAdminExportAICosts', message: err.message });
    throw toParseError(err);
  }
});
