/**
 * USD-per-million-token pricing for OpenAI Chat Completions models, used
 * to convert a call's raw `usage` (prompt_tokens/completion_tokens) into
 * an estimated cost. OpenAI has no pricing API, so this table is
 * maintained by hand -- verify against https://openai.com/api/pricing
 * before trusting any dollar figure this produces, and add an entry
 * whenever OPENAI_MODEL changes to a model not listed here.
 *
 * Prices are approximate: they use the standard (non-cached-input) input
 * rate even though `usage.prompt_tokens` may include tokens OpenAI
 * actually billed at a discounted cached rate. Good enough for relative
 * cost tracking across cases; not exact-to-the-cent billing reconciliation.
 */
const PRICING_USD_PER_MILLION_TOKENS = {
  'gpt-4o': { input: 2.5, output: 10 },
  'gpt-4o-mini': { input: 0.15, output: 0.6 },
};

/**
 * Returns the estimated cost in USD for one call, or `null` if `model`
 * isn't in the pricing table above (an unrecognized/unpriced model never
 * gets a guessed number -- callers still record the token counts, just
 * without a dollar figure attached).
 */
function estimateCostUSD(model, usage) {
  const pricing = PRICING_USD_PER_MILLION_TOKENS[model];
  if (!pricing || !usage) {
    return null;
  }
  const promptTokens = usage.prompt_tokens || 0;
  const completionTokens = usage.completion_tokens || 0;
  const inputCost = (promptTokens / 1_000_000) * pricing.input;
  const outputCost = (completionTokens / 1_000_000) * pricing.output;
  return inputCost + outputCost;
}

module.exports = { PRICING_USD_PER_MILLION_TOKENS, estimateCostUSD };
