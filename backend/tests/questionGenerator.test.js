jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const questionGenerator = require('../cloud/ai/questionGenerator');
const { AIResponseError } = require('../cloud/utils/errors');

describe('questionGenerator.generateNextQuestion', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns needsQuestion=true with a well-formed question', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {
        needsQuestion: true,
        question: { text: 'When did the hypotension begin?', category: 'timing', reason: 'Timing matters.' },
      },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await questionGenerator.generateNextQuestion({ extractedCase: {}, conversation: [], caseId: 'c1' });

    expect(result.needsQuestion).toBe(true);
    expect(result.question.text).toBe('When did the hypotension begin?');
  });

  it('returns needsQuestion=false with a null question', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { needsQuestion: false, question: null },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await questionGenerator.generateNextQuestion({ extractedCase: {}, conversation: [], caseId: 'c1' });

    expect(result).toEqual(expect.objectContaining({ needsQuestion: false, question: null }));
  });

  it('throws AIResponseError when needsQuestion is true but the question is malformed', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { needsQuestion: true, question: { text: 'Missing category and reason.' } },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      questionGenerator.generateNextQuestion({ extractedCase: {}, conversation: [], caseId: 'c1' })
    ).rejects.toThrow(AIResponseError);
  });

  it('throws AIResponseError when needsQuestion is missing entirely', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {},
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      questionGenerator.generateNextQuestion({ extractedCase: {}, conversation: [], caseId: 'c1' })
    ).rejects.toThrow(AIResponseError);
  });
});
