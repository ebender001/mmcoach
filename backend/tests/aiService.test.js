jest.mock('https');
const https = require('https');
const aiService = require('../cloud/services/aiService');
const { AIProviderError } = require('../cloud/utils/errors');

function mockHttpsResponse({ statusCode, body }) {
  https.request.mockImplementation((_options, callback) => {
    const res = {
      statusCode,
      on: (event, handler) => {
        if (event === 'data') handler(Buffer.from(body));
        if (event === 'end') handler();
      },
    };
    callback(res);
    return { on: () => {}, write: () => {}, end: () => {}, destroy: () => {} };
  });
}

describe('aiService.completeJSON', () => {
  beforeEach(() => {
    process.env.OPENAI_API_KEY = 'test-key';
    process.env.OPENAI_MODEL = 'gpt-test';
    process.env.OPENAI_MAX_RETRIES = '0';
  });

  afterEach(() => {
    jest.clearAllMocks();
    delete process.env.OPENAI_API_KEY;
    delete process.env.OPENAI_MODEL;
    delete process.env.OPENAI_MAX_RETRIES;
  });

  it('returns parsed data and metadata on a successful call', async () => {
    mockHttpsResponse({
      statusCode: 200,
      body: JSON.stringify({
        choices: [{ message: { content: JSON.stringify({ hello: 'world' }) } }],
        usage: { total_tokens: 42 },
      }),
    });

    const result = await aiService.completeJSON({ system: 's', user: 'u', operation: 'test' });

    expect(result.data).toEqual({ hello: 'world' });
    expect(result.meta.model).toBe('gpt-test');
    expect(result.meta.usage).toEqual({ total_tokens: 42 });
  });

  it('throws AIProviderError on a non-2xx status', async () => {
    mockHttpsResponse({ statusCode: 500, body: '{}' });

    await expect(aiService.completeJSON({ system: 's', user: 'u', operation: 'test' })).rejects.toThrow(
      AIProviderError
    );
  });

  it('throws AIProviderError when the message content is not valid JSON', async () => {
    mockHttpsResponse({
      statusCode: 200,
      body: JSON.stringify({ choices: [{ message: { content: 'not json' } }] }),
    });

    await expect(aiService.completeJSON({ system: 's', user: 'u', operation: 'test' })).rejects.toThrow(
      AIProviderError
    );
  });

  it('throws AIProviderError when the envelope itself is not valid JSON', async () => {
    mockHttpsResponse({ statusCode: 200, body: 'not even json' });

    await expect(aiService.completeJSON({ system: 's', user: 'u', operation: 'test' })).rejects.toThrow(
      AIProviderError
    );
  });

  it('throws AIProviderError when OPENAI_API_KEY is not configured', async () => {
    delete process.env.OPENAI_API_KEY;

    await expect(aiService.completeJSON({ system: 's', user: 'u', operation: 'test' })).rejects.toThrow(
      AIProviderError
    );
  });
});
