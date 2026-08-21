const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, cloudRegistry } = createFakeParse();
global.Parse = Parse;

jest.mock('../cloud/services/caseService');
jest.mock('../cloud/services/pubmedService');
jest.mock('../cloud/services/accountService');
jest.mock('../cloud/ai/referenceQueryBuilder');
jest.mock('../cloud/ai/dictationCorrector');
const caseService = require('../cloud/services/caseService');
const pubmedService = require('../cloud/services/pubmedService');
const accountService = require('../cloud/services/accountService');
const referenceQueryBuilder = require('../cloud/ai/referenceQueryBuilder');
const dictationCorrector = require('../cloud/ai/dictationCorrector');
const { NotFoundError, InvalidStateError } = require('../cloud/utils/errors');

require('../cloud/functions/createCase');
require('../cloud/functions/answerQuestion');
require('../cloud/functions/finalizeCase');
require('../cloud/functions/getCase');
require('../cloud/functions/checkFreeCaseEligibility');
require('../cloud/functions/redeemFreeCase');
require('../cloud/functions/updatePolishedNarrative');
require('../cloud/functions/getCaseAICost');
require('../cloud/functions/findReferences');
require('../cloud/functions/correctDictation');
require('../cloud/functions/deleteAccount');

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

describe('mmCheckFreeCaseEligibility', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmCheckFreeCaseEligibility({ params: { deviceId: 'device1' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.checkFreeCaseEligibility).not.toHaveBeenCalled();
  });

  it('rejects a missing deviceId', async () => {
    await expect(
      cloudRegistry.mmCheckFreeCaseEligibility({ params: {}, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.checkFreeCaseEligibility).not.toHaveBeenCalled();
  });

  it('returns the caller\'s free-case eligibility for this device', async () => {
    caseService.checkFreeCaseEligibility.mockResolvedValue({ eligible: true });

    const result = await cloudRegistry.mmCheckFreeCaseEligibility({
      params: { deviceId: 'device1' },
      user: AUTH_USER,
    });

    expect(caseService.checkFreeCaseEligibility).toHaveBeenCalledWith({ ownerId: 'user1', deviceId: 'device1' });
    expect(result.eligible).toBe(true);
  });
});

describe('mmRedeemFreeCase', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmRedeemFreeCase({ params: { deviceId: 'device1' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.redeemFreeCase).not.toHaveBeenCalled();
  });

  it('rejects a missing deviceId', async () => {
    await expect(
      cloudRegistry.mmRedeemFreeCase({ params: {}, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.redeemFreeCase).not.toHaveBeenCalled();
  });

  it('redeems the free case for this account/device and confirms', async () => {
    caseService.redeemFreeCase.mockResolvedValue(undefined);

    const result = await cloudRegistry.mmRedeemFreeCase({
      params: { deviceId: 'device1' },
      user: AUTH_USER,
    });

    expect(caseService.redeemFreeCase).toHaveBeenCalledWith({ ownerId: 'user1', deviceId: 'device1' });
    expect(result).toEqual({ redeemed: true });
  });

  it('propagates an invalid-state error when no free case is available', async () => {
    caseService.redeemFreeCase.mockRejectedValue(new InvalidStateError('A free case is not available for this account.'));

    await expect(
      cloudRegistry.mmRedeemFreeCase({ params: { deviceId: 'device1' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.OPERATION_FORBIDDEN });
  });
});

describe('mmUpdatePolishedNarrative', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmUpdatePolishedNarrative({ params: { caseId: 'abc123', polishedNarrative: 'Edited narrative text.' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(caseService.updatePolishedNarrative).not.toHaveBeenCalled();
  });

  it('rejects a missing polishedNarrative', async () => {
    await expect(
      cloudRegistry.mmUpdatePolishedNarrative({ params: { caseId: 'abc123' }, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.updatePolishedNarrative).not.toHaveBeenCalled();
  });

  it('rejects a narrative that is too short', async () => {
    await expect(
      cloudRegistry.mmUpdatePolishedNarrative({ params: { caseId: 'abc123', polishedNarrative: 'too short' }, user: AUTH_USER })
    ).rejects.toThrow();
    expect(caseService.updatePolishedNarrative).not.toHaveBeenCalled();
  });

  it('propagates an invalid-state error when the case is not yet finalized', async () => {
    caseService.updatePolishedNarrative.mockRejectedValue(new InvalidStateError('This case has not been finalized yet.'));

    await expect(
      cloudRegistry.mmUpdatePolishedNarrative({
        params: { caseId: 'abc123', polishedNarrative: 'Edited narrative text.' },
        user: AUTH_USER,
      })
    ).rejects.toMatchObject({ code: Parse.Error.OPERATION_FORBIDDEN });
  });

  it('saves the edited narrative and returns the finalized response shape', async () => {
    caseService.updatePolishedNarrative.mockResolvedValue({ objectId: 'abc123', status: 'completed' });
    caseService.formatFinalizedCase.mockReturnValue({
      caseId: 'abc123',
      status: 'completed',
      polishedNarrative: 'Edited narrative text.',
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
    });

    const result = await cloudRegistry.mmUpdatePolishedNarrative({
      params: { caseId: 'abc123', polishedNarrative: 'Edited narrative text.' },
      user: AUTH_USER,
    });

    expect(caseService.updatePolishedNarrative).toHaveBeenCalledWith({
      caseId: 'abc123',
      ownerId: 'user1',
      polishedNarrative: 'Edited narrative text.',
    });
    expect(result.polishedNarrative).toBe('Edited narrative text.');
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

describe('mmFindReferences', () => {
  const AI_QUERY_META = { model: 'gpt-4o', latencyMs: 5, usage: { total_tokens: 40 } };

  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmFindReferences({ params: { topic: 'Postoperative bleeding' } })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(pubmedService.findReferences).not.toHaveBeenCalled();
  });

  it('rejects a missing topic', async () => {
    await expect(cloudRegistry.mmFindReferences({ params: {}, user: AUTH_USER })).rejects.toThrow();
    expect(pubmedService.findReferences).not.toHaveBeenCalled();
  });

  it('searches PubMed using the AI-crafted query, not the raw topic', async () => {
    referenceQueryBuilder.buildQuery.mockResolvedValue({
      query: '(postoperative hemorrhage[mesh]) AND (cardiac surgical procedures[mesh])',
      meta: AI_QUERY_META,
    });
    pubmedService.findReferences.mockResolvedValue([
      { pmid: '111', title: 'A relevant paper', authors: ['Smith J'], journal: 'J Surg', year: '2020', abstractSections: [{ label: null, text: 'Abstract text.' }], url: 'https://pubmed.ncbi.nlm.nih.gov/111/' },
    ]);

    const result = await cloudRegistry.mmFindReferences({
      params: { topic: 'Postoperative bleeding after cardiac surgery', searchIntent: 'Guidelines on re-exploration timing.' },
      user: AUTH_USER,
    });

    expect(referenceQueryBuilder.buildQuery).toHaveBeenCalledWith({
      topic: 'Postoperative bleeding after cardiac surgery',
      searchIntent: 'Guidelines on re-exploration timing.',
    });
    expect(pubmedService.findReferences).toHaveBeenCalledWith({
      query: '(postoperative hemorrhage[mesh]) AND (cardiac surgical procedures[mesh])',
      maxResults: 5,
    });
    expect(result.topic).toBe('Postoperative bleeding after cardiac surgery');
    expect(result.results).toHaveLength(1);
  });

  it('falls back to the plain topic when the AI-crafted query returns nothing', async () => {
    referenceQueryBuilder.buildQuery.mockResolvedValue({
      query: '(overly narrow query[mesh]) AND (too specific[tiab])',
      meta: AI_QUERY_META,
    });
    pubmedService.findReferences
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { pmid: '222', title: 'Fallback result', authors: [], journal: null, year: null, abstractSections: [], url: 'https://pubmed.ncbi.nlm.nih.gov/222/' },
      ]);

    const result = await cloudRegistry.mmFindReferences({
      params: { topic: 'Postoperative bleeding' },
      user: AUTH_USER,
    });

    expect(pubmedService.findReferences).toHaveBeenNthCalledWith(1, {
      query: '(overly narrow query[mesh]) AND (too specific[tiab])',
      maxResults: 5,
    });
    expect(pubmedService.findReferences).toHaveBeenNthCalledWith(2, { query: 'Postoperative bleeding', maxResults: 5 });
    expect(result.results).toHaveLength(1);
  });

  it('verifies case ownership and records AI usage when caseId is provided', async () => {
    referenceQueryBuilder.buildQuery.mockResolvedValue({
      query: 'postoperative bleeding[tiab]',
      meta: AI_QUERY_META,
    });
    pubmedService.findReferences.mockResolvedValue([]);
    caseService.getCase.mockResolvedValue({ objectId: 'case1', ownerId: 'user1' });

    await cloudRegistry.mmFindReferences({
      params: { topic: 'Postoperative bleeding', caseId: 'case1' },
      user: AUTH_USER,
    });

    expect(caseService.getCase).toHaveBeenCalledWith({ caseId: 'case1', ownerId: 'user1' });
    expect(caseService.recordAIUsage).toHaveBeenCalledWith({
      caseId: 'case1',
      ownerId: 'user1',
      operation: 'buildReferenceQuery',
      meta: AI_QUERY_META,
    });
  });

  it('propagates NotFoundError when caseId does not belong to the caller', async () => {
    caseService.getCase.mockRejectedValue(new NotFoundError('No case found with id case1.'));

    await expect(
      cloudRegistry.mmFindReferences({ params: { topic: 'Postoperative bleeding', caseId: 'case1' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.OBJECT_NOT_FOUND });
    expect(referenceQueryBuilder.buildQuery).not.toHaveBeenCalled();
  });

  it('propagates a PubMed failure as an internal-server-error Parse error', async () => {
    const { ExternalServiceError } = require('../cloud/utils/errors');
    referenceQueryBuilder.buildQuery.mockResolvedValue({ query: 'Postoperative bleeding', meta: AI_QUERY_META });
    pubmedService.findReferences.mockRejectedValue(new ExternalServiceError('Failed to reach PubMed.'));

    await expect(
      cloudRegistry.mmFindReferences({ params: { topic: 'Postoperative bleeding' }, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.INTERNAL_SERVER_ERROR });
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

describe('mmDeleteAccount', () => {
  it('rejects an unauthenticated request without calling the service', async () => {
    await expect(
      cloudRegistry.mmDeleteAccount({ params: {} })
    ).rejects.toMatchObject({ code: Parse.Error.INVALID_SESSION_TOKEN });
    expect(accountService.deleteAccount).not.toHaveBeenCalled();
  });

  it('deletes the caller\'s own account and confirms', async () => {
    accountService.deleteAccount.mockResolvedValue(undefined);

    const result = await cloudRegistry.mmDeleteAccount({ params: {}, user: AUTH_USER });

    expect(accountService.deleteAccount).toHaveBeenCalledWith('user1');
    expect(result).toEqual({ deleted: true });
  });

  it('propagates a failure from the service as a Parse error', async () => {
    accountService.deleteAccount.mockRejectedValue(new Error('backend unavailable'));

    await expect(
      cloudRegistry.mmDeleteAccount({ params: {}, user: AUTH_USER })
    ).rejects.toMatchObject({ code: Parse.Error.INTERNAL_SERVER_ERROR });
  });
});
