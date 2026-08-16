/**
 * Minimal structured-ish logger for Back4App Cloud Code logs.
 *
 * Deliberately takes a fields object rather than free-form strings so log
 * lines stay greppable, e.g.:
 *   [MMCoach] function=mmAnswerQuestion caseId=abc123 operation=nextQuestion model=gpt-4o-mini latencyMs=1240
 *
 * Never pass full narratives, answers, or AI-generated prose to this logger.
 */
function formatLine(fields) {
  return Object.entries(fields)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${key}=${value}`)
    .join(' ');
}

function info(fields) {
  console.log(`[MMCoach] ${formatLine(fields)}`);
}

function warn(fields) {
  console.warn(`[MMCoach] ${formatLine(fields)}`);
}

function error(fields) {
  console.error(`[MMCoach] ${formatLine(fields)}`);
}

module.exports = { info, warn, error };
