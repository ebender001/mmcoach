/**
 * Centralized MMCase status values. Nothing else in the codebase should
 * reference raw status strings -- import CaseStatus instead.
 */
const CaseStatus = Object.freeze({
  COLLECTING_INFORMATION: 'collecting_information',
  READY_TO_FINALIZE: 'ready_to_finalize',
  COMPLETED: 'completed',
});

const ALL_STATUSES = Object.freeze(Object.values(CaseStatus));

function isValidStatus(status) {
  return ALL_STATUSES.includes(status);
}

module.exports = { CaseStatus, ALL_STATUSES, isValidStatus };
