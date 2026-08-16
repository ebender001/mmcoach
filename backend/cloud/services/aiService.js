/**
 * Centralized AI provider access. This is the ONLY module that talks to
 * OpenAI. ai/* modules call completeJSON(); nothing else should.
 *
 * Uses Node's built-in https module rather than a fetch/axios dependency to
 * keep Cloud Code deployment dependency-free.
 */
const https = require('https');
const aiConfig = require('../config/aiConfig');
const logger = require('../utils/logger');
const { AIProviderError } = require('../utils/errors');

const OPENAI_HOST = 'api.openai.com';
const OPENAI_PATH = '/v1/chat/completions';

function postJSON(payload, { apiKey, timeoutMs }) {
  const body = JSON.stringify(payload);

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: OPENAI_HOST,
        path: OPENAI_PATH,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
          Authorization: `Bearer ${apiKey}`,
        },
        timeout: timeoutMs,
      },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => {
          raw += chunk;
        });
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, raw });
        });
      }
    );

    req.on('timeout', () => {
      req.destroy(new Error('OpenAI request timed out.'));
    });
    req.on('error', (err) => reject(err));
    req.write(body);
    req.end();
  });
}

async function requestWithRetry(payload, options, attemptsLeft, context) {
  const startedAt = Date.now();
  try {
    const { statusCode, raw } = await postJSON(payload, options);
    const latencyMs = Date.now() - startedAt;

    if (statusCode < 200 || statusCode >= 300) {
      const retriable = statusCode === 429 || statusCode >= 500;
      if (retriable && attemptsLeft > 0) {
        logger.warn({ ...context, event: 'openai_retry', statusCode, latencyMs });
        return requestWithRetry(payload, options, attemptsLeft - 1, context);
      }
      logger.error({ ...context, event: 'openai_error', statusCode, latencyMs });
      throw new AIProviderError(`AI provider returned status ${statusCode}.`);
    }

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (parseErr) {
      logger.error({ ...context, event: 'openai_bad_envelope', latencyMs });
      throw new AIProviderError('AI provider returned an unparseable response.');
    }

    logger.info({ ...context, event: 'openai_success', model: payload.model, latencyMs });
    return { parsed, latencyMs };
  } catch (err) {
    if (err instanceof AIProviderError) {
      throw err;
    }
    if (attemptsLeft > 0) {
      logger.warn({ ...context, event: 'openai_retry_after_error', message: err.message });
      return requestWithRetry(payload, options, attemptsLeft - 1, context);
    }
    logger.error({ ...context, event: 'openai_failure', message: err.message });
    throw new AIProviderError(`Failed to reach AI provider: ${err.message}`);
  }
}

/**
 * Sends a system+user prompt pair to the AI provider in JSON mode and
 * returns the parsed JSON body along with call metadata.
 *
 * @param {object} params
 * @param {string} params.system - system prompt content
 * @param {string} params.user - user prompt content
 * @param {number} [params.temperature]
 * @param {string} params.operation - short label for logging, e.g. "generateNextQuestion"
 * @param {string} [params.caseId] - for logging correlation only
 */
async function completeJSON({ system, user, temperature = 0.2, operation, caseId }) {
  const apiKey = aiConfig.getOpenAIApiKey();
  if (!apiKey) {
    throw new AIProviderError('OPENAI_API_KEY is not configured.');
  }

  const model = aiConfig.getModel();
  const payload = {
    model,
    temperature,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user },
    ],
  };

  const context = { operation, caseId };
  const { parsed, latencyMs } = await requestWithRetry(
    payload,
    { apiKey, timeoutMs: aiConfig.getRequestTimeoutMs() },
    aiConfig.getMaxRetries(),
    context
  );

  const choice = parsed.choices && parsed.choices[0];
  const content = choice && choice.message && choice.message.content;
  if (!content) {
    throw new AIProviderError('AI provider response did not contain message content.');
  }

  let data;
  try {
    data = JSON.parse(content);
  } catch (parseErr) {
    throw new AIProviderError('AI provider returned invalid JSON content.');
  }

  return {
    data,
    meta: {
      model,
      latencyMs,
      usage: parsed.usage || null,
    },
  };
}

module.exports = { completeJSON };
