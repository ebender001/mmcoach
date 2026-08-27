jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const facultyQuestionAnswerer = require('../cloud/ai/facultyQuestionAnswerer');
const { AIResponseError } = require('../cloud/utils/errors');

describe('facultyQuestionAnswerer.answerQuestion', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns the AI-drafted answer', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { answer: 'Imaging was obtained once transfusion requirements began escalating.' },
      meta: { model: 'gpt-test', latencyMs: 5, usage: { total_tokens: 40 } },
    });

    const result = await facultyQuestionAnswerer.answerQuestion({
      extractedCase: { procedure: 'CABG x3' },
      conversation: [{ question: 'When did bleeding start?', answer: 'About four hours postop.' }],
      polishedNarrative: 'A 68-year-old man underwent CABG x3...',
      question: 'What prompted the decision to obtain imaging at that point?',
      caseId: 'case1',
    });

    expect(result.answer).toBe('Imaging was obtained once transfusion requirements began escalating.');
    expect(result.meta.usage).toEqual({ total_tokens: 40 });
    expect(result.promptVersion).toBe('1.0.0');
  });

  it('throws AIResponseError when the response has no answer', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {},
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      facultyQuestionAnswerer.answerQuestion({
        extractedCase: {},
        conversation: [],
        polishedNarrative: '',
        question: 'What prompted the decision to obtain imaging at that point?',
        caseId: 'case1',
      })
    ).rejects.toThrow(AIResponseError);
  });
});
