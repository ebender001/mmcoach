/**
 * Tracks which devices have already redeemed their free first case --
 * independent of any account, and deliberately outlives account deletion.
 * This is what stops "delete account, sign up again" from resetting the
 * first-case-free offer: eligibility is account-case-count == 0 AND this
 * device hasn't redeemed before (see services/caseService.js).
 *
 * `deviceId` is an opaque UUID generated and Keychain-persisted on the
 * client (survives app deletion/reinstall -- see
 * DeviceIdentifierService.swift); it identifies a device, not a person,
 * and is never linked to account data.
 */
const REDEMPTION_CLASS_NAME = 'MMDeviceFreeCaseRedemption';

function getRedemptionClass() {
  return Parse.Object.extend(REDEMPTION_CLASS_NAME);
}

/** Whether this device has already redeemed its free first case. */
async function hasRedeemed(deviceId) {
  const RedemptionClass = getRedemptionClass();
  const query = new Parse.Query(RedemptionClass);
  query.equalTo('deviceId', deviceId);
  const count = await query.count({ useMasterKey: true });
  return count > 0;
}

/**
 * Records that this device has now redeemed its free first case.
 * Idempotent -- safe to call even if the device is already recorded,
 * which matters since `redeemFreeCase` re-checks then records in two
 * separate steps (see caseService.js).
 */
async function recordRedemption(deviceId) {
  const alreadyRedeemed = await hasRedeemed(deviceId);
  if (alreadyRedeemed) return;

  const RedemptionClass = getRedemptionClass();
  const row = new RedemptionClass();
  row.set('deviceId', deviceId);

  const acl = new Parse.ACL();
  acl.setPublicReadAccess(false);
  acl.setPublicWriteAccess(false);
  row.setACL(acl);

  await row.save(null, { useMasterKey: true });
}

module.exports = { hasRedeemed, recordRedemption, CLASS_NAME: REDEMPTION_CLASS_NAME };
