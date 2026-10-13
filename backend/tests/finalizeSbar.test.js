const { validateFinalizeCaseResponse } = require('../cloud/schemas/aiResponseSchemas');

function baseResponse(overrides = {}) {
  return {
    polishedNarrative: 'A narrative.',
    discussionPreparation: [{ topic: 't', whyItMatters: 'w', prepareToDiscuss: 'p' }],
    likelyFacultyQuestions: ['A question?'],
    referenceTopics: [],
    ...overrides,
  };
}

describe('validateFinalizeCaseResponse sbar', () => {
  it('returns a trimmed sbar object when all four fields are present', () => {
    const result = validateFinalizeCaseResponse(baseResponse({
      sbar: { situation: ' s ', background: 'b', assessment: 'a', recommendation: 'r' },
    }));
    expect(result.sbar).toEqual({ situation: 's', background: 'b', assessment: 'a', recommendation: 'r' });
  });

  it('returns null rather than failing when sbar is missing', () => {
    expect(validateFinalizeCaseResponse(baseResponse()).sbar).toBeNull();
  });

  it('returns null when any sbar field is missing or blank', () => {
    const result = validateFinalizeCaseResponse(baseResponse({
      sbar: { situation: 's', background: '  ', assessment: 'a', recommendation: 'r' },
    }));
    expect(result.sbar).toBeNull();
  });
});
