/**
 * The extracted case is intentionally flexible: not every field applies to
 * every case, and the AI decides which are relevant. This list exists to
 * guide prompt construction and documentation, not to enforce a rigid shape.
 */
const EXTRACTED_CASE_FIELDS = Object.freeze([
  'demographicSummary',
  'presentingProblem',
  'indication',
  'relevantComorbidities',
  'procedure',
  'intraoperativeEvents',
  'postoperativeCourse',
  'complication',
  'clinicalDeterioration',
  'timing',
  'vitalSigns',
  'laboratoryResults',
  'laboratoryTrends',
  'imaging',
  'medications',
  'interventions',
  'consultations',
  'escalationOfCare',
  'reoperation',
  'responseToTreatment',
  'outcome',
  'decisionPoints',
  'uncertainties',
]);

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Drops null/undefined/empty values so extractedCase only carries fields the
 * AI actually populated. Unknown field names are preserved -- the schema is
 * a guide for the AI, not an allowlist.
 */
function sanitizeExtractedCase(value) {
  if (!isPlainObject(value)) {
    return {};
  }

  const sanitized = {};
  for (const [key, val] of Object.entries(value)) {
    if (val === null || val === undefined) continue;
    if (typeof val === 'string' && val.trim() === '') continue;
    if (Array.isArray(val) && val.length === 0) continue;
    if (isPlainObject(val) && Object.keys(val).length === 0) continue;
    sanitized[key] = val;
  }
  return sanitized;
}

module.exports = { EXTRACTED_CASE_FIELDS, isPlainObject, sanitizeExtractedCase };
