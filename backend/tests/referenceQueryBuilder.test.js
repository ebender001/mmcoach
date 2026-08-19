jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const referenceQueryBuilder = require('../cloud/ai/referenceQueryBuilder');
const { AIResponseError } = require('../cloud/utils/errors');

describe('referenceQueryBuilder.buildQuery', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns the AI-crafted PubMed query string', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { query: '(postoperative hemorrhage[mesh]) AND (cardiac surgical procedures[mesh])' },
      meta: { model: 'gpt-test', latencyMs: 5, usage: { total_tokens: 40 } },
    });

    const result = await referenceQueryBuilder.buildQuery({
      topic: 'Postoperative bleeding after cardiac surgery',
      searchIntent: 'Guidelines on timing of re-exploration.',
    });

    expect(result.query).toBe('(postoperative hemorrhage[mesh]) AND (cardiac surgical procedures[mesh])');
    expect(result.meta.usage).toEqual({ total_tokens: 40 });
    expect(result.promptVersion).toBe('1.0.0');
  });

  it('throws AIResponseError when the response has no query', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {},
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      referenceQueryBuilder.buildQuery({ topic: 'Postoperative bleeding', searchIntent: '' })
    ).rejects.toThrow(AIResponseError);
  });
});
