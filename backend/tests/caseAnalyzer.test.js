jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const caseAnalyzer = require('../cloud/ai/caseAnalyzer');
const { AIResponseError } = require('../cloud/utils/errors');

describe('caseAnalyzer.analyzeInitialNarrative', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns a sanitized extractedCase on a well-formed AI response', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { extractedCase: { procedure: 'CABG x3', imaging: '' } },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await caseAnalyzer.analyzeInitialNarrative({ narrative: 'case text', caseId: 'c1' });

    expect(result.extractedCase).toEqual({ procedure: 'CABG x3' });
    expect(result.promptVersion).toBe('1.0.0');
  });

  it('throws AIResponseError when extractedCase is missing', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { somethingElse: true },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      caseAnalyzer.analyzeInitialNarrative({ narrative: 'case text', caseId: 'c1' })
    ).rejects.toThrow(AIResponseError);
  });
});

describe('caseAnalyzer.incorporateAnswer', () => {
  afterEach(() => jest.clearAllMocks());

  it('merges the AI-updated extractedCase', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { extractedCase: { procedure: 'CABG x3', timing: '4 hours post-op' } },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await caseAnalyzer.incorporateAnswer({
      extractedCase: { procedure: 'CABG x3' },
      conversation: [],
      newEntry: { question: 'When did it start?', answer: '4 hours post-op' },
      caseId: 'c1',
    });

    expect(result.extractedCase.timing).toBe('4 hours post-op');
  });
});
