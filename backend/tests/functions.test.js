const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, cloudRegistry } = createFakeParse();
global.Parse = Parse;

jest.mock('../cloud/services/caseService');
jest.mock('../cloud/ai/dictationCorrector');
const caseService = require('../cloud/services/caseService');
const dictationCorrector = require('../cloud/ai/dictationCorrector');
const { NotFoundError, InvalidStateError } = require('../cloud/utils/errors');

require('../cloud/functions/createCase');
require('../cloud/functions/answerQuestion');
require('../cloud/functions/finalizeCase');
require('../cloud/functions/getCase');
require('../cloud/functions/getCaseAICost');
require('../cloud/functions/correctDictation');

afterEach(() => jest.clearAllMocks());

/** A signed-in caller, as Parse Server would attach from a valid session token. */
const AUTH_USER = { id: 'user1' };

describe('mmCreateCase', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmCreateCase({ params: { narrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive.' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.createCase).not.toHaveBeenCalled();
  });

  it('rejects a missing narrative without calling the service', async () => {
    await expect(cloudRegistry.mmCreateCase({ params: {}, user: AUTH_USER })).rejects.toThrow();
    expect(caseService.createCase).not.toHaveBeenCalled();
  });

  it('rejects a narrative that is too short to be meaningful', async () => {
    await expect(
      cloudRegistry.mmCreateCase({ params: { narrative: 'too short' }, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.createCase).not.toHaveBeenCalled();
  });

  it('creates a case owned by the authenticated caller and returns the summary response', async () => {
    caseService.createCase.mockResolvedValue({ objectId: 'abc123', status: 'collecting_information' });
    caseService.formatCaseSummary.mockReturnValue({
      caseId: 'abc123',
      status: 'collecting_information',
      extractedCase: {},
      nextQuestion: null,
    });

    const result = await cloudRegistry.mmCreateCase({
      params: { narrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive.' },
      user: AUTH_USER,
    });

    expect(caseService.createCase).toHaveBeenCalledWith({
      narrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive.',
      ownerId: 'user1',
    });
    expect(result.caseId).toBe('abc123');
  });
});

describe('mmAnswerQuestion', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'abc123', questionId: 'q1', answer: 'yes' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.answerQuestion).not.toHaveBeenCalled();
  });

  it('rejects when answer is missing', async () => {
    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'abc123', questionId: 'q1' }, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.answerQuestion).not.toHaveBeenCalled();
  });

  it('propagates a not-found error from the service as a Parse error', async () => {
    caseService.answerQuestion.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'missing', questionId: 'q1', answer: 'yes' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.OBJECT_NOT_FOUND });
  });

  it('propagates a stale-question error as an operation-forbidden Parse error', async () => {
    caseService.answerQuestion.mockRejectedValue(new InvalidStateError('That question is no longer active.'));

    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'abc123', questionId: 'stale', answer: 'yes' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.OPERATION_FORBIDDEN });
  });

  it('answers a question owned by the caller and returns the summary response', async () => {
    caseService.answerQuestion.mockResolvedValue({ objectId: 'abc123', status: 'ready_to_finalize' });
    caseService.formatCaseSummary.mockReturnValue({
      caseId: 'abc123',
      status: 'ready_to_finalize',
      extractedCase: {},
      nextQuestion: null,
    });

    const result = await cloudRegistry.mmAnswerQuestion({
      params: { caseId: 'abc123', questionId: 'q1', answer: 'About four hours after ICU arrival.' },
      user: AUTH_USER,
    });

    expect(caseService.answerQuestion).toHaveBeenCalledWith({
      caseId: 'abc123',
      questionId: 'q1',
      answer: 'About four hours after ICU arrival.',
      ownerId: 'user1',
    });
    expect(result.status).toBe('ready_to_finalize');
  });
});

describe('mmFinalizeCase', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmFinalizeCase({ params: { caseId: 'abc123' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.finalizeCase).not.toHaveBeenCalled();
  });

  it('rejects a missing caseId', async () => {
    await expect(cloudRegistry.mmFinalizeCase({ params: {}, user: AUTH_USER })).rejects.toThrow();
    expect(caseService.finalizeCase).not.toHaveBeenCalled();
  });

  it('propagates not-found for a nonexistent case', async () => {
    caseService.finalizeCase.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(
      cloudRegistry.mmFinalizeCase({ params: { caseId: 'missing' }, user: AUTH_USER })
    ).rejects.toMatchObject({
      code: Parse.Error.OBJECT_NOT_FOUND,
    });
  });

  it('finalizes a case owned by the caller and returns the finalized response shape', async () => {
    caseService.finalizeCase.mockResolvedValue({ objectId: 'abc123', status: 'completed' });
    caseService.formatFinalizedCase.mockReturnValue({
      caseId: 'abc123',
      status: 'completed',
      polishedNarrative: 'narrative',
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
    });

    const result = await cloudRegistry.mmFinalizeCase({ params: { caseId: 'abc123' }, user: AUTH_USER });

    expect(caseService.finalizeCase).toHaveBeenCalledWith({ caseId: 'abc123', ownerId: 'user1' });
    expect(result.status).toBe('completed');
    expect(result.polishedNarrative).toBe('narrative');
  });
});

describe('mmGetCase', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmGetCase({ params: { caseId: 'abc123' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.getCase).not.toHaveBeenCalled();
  });

  it('rejects a missing caseId', async () => {
    await expect(cloudRegistry.mmGetCase({ params: {}, user: AUTH_USER })).rejects.toThrow();
    expect(caseService.getCase).not.toHaveBeenCalled();
  });

  it('propagates not-found for a nonexistent case', async () => {
    caseService.getCase.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(
      cloudRegistry.mmGetCase({ params: { caseId: 'missing' }, user: AUTH_USER })
    ).rejects.toMatchObject({
      code: Parse.Error.OBJECT_NOT_FOUND,
    });
  });

  it('returns the full case state for the caller', async () => {
    caseService.getCase.mockResolvedValue({ objectId: 'abc123', status: 'completed' });
    caseService.formatFullCase.mockReturnValue({ caseId: 'abc123', status: 'completed' });

    const result = await cloudRegistry.mmGetCase({ params: { caseId: 'abc123' }, user: AUTH_USER });

    expect(caseService.getCase).toHaveBeenCalledWith({ caseId: 'abc123', ownerId: 'user1' });
    expect(result.caseId).toBe('abc123');
  });
});

describe('mmGetCaseAICost', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmGetCaseAICost({ params: { caseId: 'abc123' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.getCaseAICost).not.toHaveBeenCalled();
  });

  it('rejects a missing caseId', async () => {
    await expect(cloudRegistry.mmGetCaseAICost({ params: {}, user: AUTH_USER })).rejects.toThrow();
    expect(caseService.getCaseAICost).not.toHaveBeenCalled();
  });

  it('propagates not-found for a case that does not belong to the caller', async () => {
    caseService.getCaseAICost.mockRejectedValue(new NotFoundError('No case found with id abc123.'));

    await expect(
      cloudRegistry.mmGetCaseAICost({ params: { caseId: 'abc123' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.OBJECT_NOT_FOUND });
  });

  it('returns the cost breakdown for the caller', async () => {
    caseService.getCaseAICost.mockResolvedValue({
      caseId: 'abc123',
      totalCostUSD: 0.0234,
      totalTokens: 900,
      calls: [{ objectId: 'ac1', operation: 'analyzeInitialNarrative', model: 'gpt-4o', costUSD: 0.0234, totalTokens: 900 }],
    });

    const result = await cloudRegistry.mmGetCaseAICost({ params: { caseId: 'abc123' }, user: AUTH_USER });

    expect(caseService.getCaseAICost).toHaveBeenCalledWith({ caseId: 'abc123', ownerId: 'user1' });
    expect(result.totalCostUSD).toBe(0.0234);
    expect(result.calls).toHaveLength(1);
  });
});

describe('mmCorrectDictation', () => {
  it('rejects a missing newSegment without calling the corrector', async () => {
    await expect(cloudRegistry.mmCorrectDictation({ params: {} })).rejects.toThrow();
    expect(dictationCorrector.correctSegment).not.toHaveBeenCalled();
  });

  it('defaults priorNarrative to an empty string when omitted', async () => {
    dictationCorrector.correctSegment.mockResolvedValue({
      correctedSegment: 'saphenous vein graft',
      changes: [],
    });

    await cloudRegistry.mmCorrectDictation({ params: { newSegment: 'saphenous vein graft' } });

    expect(dictationCorrector.correctSegment).toHaveBeenCalledWith({
      priorNarrative: '',
      newSegment: 'saphenous vein graft',
    });
  });

  it('returns the corrected segment and changes', async () => {
    dictationCorrector.correctSegment.mockResolvedValue({
      correctedSegment: 'saphenous vein graft to the right coronary artery',
      changes: [{ original: 'sadness', corrected: 'saphenous' }],
    });

    const result = await cloudRegistry.mmCorrectDictation({
      params: {
        priorNarrative: 'The patient underwent three vessel bypass surgery.',
        newSegment: 'sadness vein graft to the right coronary artery',
      },
    });

    expect(result.correctedSegment).toBe('saphenous vein graft to the right coronary artery');
    expect(result.changes).toEqual([{ original: 'sadness', corrected: 'saphenous' }]);
  });
});
