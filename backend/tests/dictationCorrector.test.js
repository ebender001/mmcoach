jest.mock('../cloud/services/aiService');
const aiService = require('../cloud/services/aiService');
const dictationCorrector = require('../cloud/ai/dictationCorrector');
const { AIResponseError } = require('../cloud/utils/errors');

describe('dictationCorrector.correctSegment', () => {
  afterEach(() => jest.clearAllMocks());

  it('returns the corrected segment and changes on a well-formed AI response', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: {
        correctedSegment: 'saphenous vein graft to the right coronary artery',
        changes: [
          { original: 'sadness', corrected: 'saphenous' },
          { original: 'corner', corrected: 'coronary' },
        ],
      },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await dictationCorrector.correctSegment({
      priorNarrative: 'The patient underwent three vessel bypass surgery.',
      newSegment: 'sadness vein graft to the right corner artery',
    });

    expect(result.correctedSegment).toBe('saphenous vein graft to the right coronary artery');
    expect(result.changes).toEqual([
      { original: 'sadness', corrected: 'saphenous' },
      { original: 'corner', corrected: 'coronary' },
    ]);
    expect(result.promptVersion).toBe('1.0.0');
  });

  it('defaults to an empty changes array when the AI made no changes', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { correctedSegment: 'the patient tolerated the procedure well' },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    const result = await dictationCorrector.correctSegment({
      priorNarrative: '',
      newSegment: 'the patient tolerated the procedure well',
    });

    expect(result.changes).toEqual([]);
  });

  it('throws AIResponseError when correctedSegment is missing', async () => {
    aiService.completeJSON.mockResolvedValue({
      data: { changes: [] },
      meta: { model: 'gpt-test', latencyMs: 5 },
    });

    await expect(
      dictationCorrector.correctSegment({ priorNarrative: '', newSegment: 'some segment' })
    ).rejects.toThrow(AIResponseError);
  });
});
