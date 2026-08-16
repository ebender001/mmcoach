jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const finalizer = require('../cloud/ai/finalizer');
const { AIResponseError } = require('../cloud/utils/errors');

describe('finalizer.finalizeCase', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns a polished narrative, discussion prep, questions, and pending references', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {
        polishedNarrative: 'A 68-year-old man underwent CABG x3...',
        discussionPreparation: [
          { topic: 'Timing of re-exploration', whyItMatters: 'Bleeding worsened.', prepareToDiscuss: 'Thresholds for re-exploration.' },
        ],
        likelyFacultyQuestions: ['What made you decide to return to the OR when you did?'],
        referenceTopics: [{ topic: 'Postoperative bleeding after cardiac surgery', searchIntent: 'Guidelines on re-exploration timing.' }],
      },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await finalizer.finalizeCase({
      extractedCase: {},
      conversation: [],
      originalNarrative: 'narrative',
      caseId: 'c1',
    });

    expect(result.polishedNarrative).toContain('CABG');
    expect(result.discussionPreparation).toHaveLength(1);
    expect(result.likelyFacultyQuestions).toHaveLength(1);
    expect(result.references).toEqual([
      {
        topic: 'Postoperative bleeding after cardiac surgery',
        searchIntent: 'Guidelines on re-exploration timing.',
        citation: null,
        verified: false,
      },
    ]);
  });

  it('throws AIResponseError when discussionPreparation is missing', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {
        polishedNarrative: 'narrative',
        discussionPreparation: [],
        likelyFacultyQuestions: ['A question?'],
        referenceTopics: [],
      },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      finalizer.finalizeCase({ extractedCase: {}, conversation: [], originalNarrative: 'n', caseId: 'c1' })
    ).rejects.toThrow(AIResponseError);
  });

  it('throws AIResponseError on malformed (non-JSON-shaped) AI output', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: 'not an object',
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      finalizer.finalizeCase({ extractedCase: {}, conversation: [], originalNarrative: 'n', caseId: 'c1' })
    ).rejects.toThrow(AIResponseError);
  });
});
