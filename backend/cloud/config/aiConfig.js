/**
 * Centralized AI provider configuration. No other module should read
 * OPENAI_* environment variables directly or hard-code a model name.
 *
 * On Back4App, set these under Server Settings > Environment Variables.
 */
const DEFAULT_MODEL = 'gpt-4o-mini';
const DEFAULT_TIMEOUT_MS = 30000;
const DEFAULT_MAX_RETRIES = 2;

function getOpenAIApiKey() {
  return process.env.OPENAI_API_KEY || '';
}

function getModel() {
  return process.env.OPENAI_MODEL || DEFAULT_MODEL;
}

function getRequestTimeoutMs() {
  const parsed = parseInt(process.env.OPENAI_TIMEOUT_MS, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_TIMEOUT_MS;
}

function getMaxRetries() {
  const parsed = parseInt(process.env.OPENAI_MAX_RETRIES, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_MAX_RETRIES;
}

module.exports = {
  DEFAULT_MODEL,
  getOpenAIApiKey,
  getModel,
  getRequestTimeoutMs,
  getMaxRetries,
};
