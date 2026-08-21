/**
 * Account-level operations that span more than one Parse class -- for now,
 * just deletion. Kept separate from caseService (which is scoped to the
 * case-preparation workflow) since this is account lifecycle, not case
 * lifecycle.
 */
const caseRepository = require('../repositories/caseRepository');
const aiCostRepository = require('../repositories/aiCostRepository');
const logger = require('../utils/logger');

/**
 * Permanently deletes a user's account and every case/AI-cost record they
 * own, in that order (case/cost data first, the account last) so a
 * failure partway through never leaves an orphaned account with no data
 * to show for it. Irreversible -- the client (AccountView) is responsible
 * for confirming with the person before calling this.
 *
 * Also destroys the user's active Parse sessions so any other
 * signed-in device is logged out immediately (its next request fails
 * with an invalid-session error, the same path already used for expired
 * sessions -- see BackendService.mmSessionExpired on the client), rather
 * than continuing to work against a deleted account until its session
 * happens to expire naturally.
 */
async function deleteAccount(userId) {
  await aiCostRepository.deleteAllForOwner(userId);
  await caseRepository.deleteAllForOwner(userId);

  const sessionQuery = new Parse.Query(Parse.Session);
  sessionQuery.equalTo('user', Parse.User.createWithoutData(userId));
  sessionQuery.limit(1000);
  const sessions = await sessionQuery.find({ useMasterKey: true });
  if (sessions.length > 0) {
    await Parse.Object.destroyAll(sessions, { useMasterKey: true });
  }

  const user = Parse.User.createWithoutData(userId);
  await user.destroy({ useMasterKey: true });

  logger.info({ module: 'accountService', operation: 'deleteAccount', userId });
}

module.exports = { deleteAccount };
