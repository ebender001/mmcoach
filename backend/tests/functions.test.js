const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, cloudRegistry } = createFakeParse();
global.Parse = Parse;

jest.mock('../cloud/services/caseService');
const caseService = require('../cloud/services/caseService');
const { NotFoundError, InvalidStateError } = require('../cloud/utils/errors');

require('../cloud/functions/createCase');
require('../cloud/functions/answerQuestion');
require('../cloud/functions/finalizeCase');
require('../cloud/functions/getCase');

afterEach(() => jest.clearAllMocks());

describe('mmCreateCase', () => {
  it('rejects a missing narrative without calling the service', async () => {
    await expect(cloudRegistry.mmCreateCase({ params: {} })).rejects.toThrow();
    expect(caseService.createCase).not.toHaveBeenCalled();
  });

  it('rejects a narrative that is too short to be meaningful', async () => {
    await expect(cloudRegistry.mmCreateCase({ params: { narrative: 'too short' } })).rejects.toThrow();
    expect(caseService.createCase).not.toHaveBeenCalled();
  });

  it('creates a case and returns the summary response', async () => {
    caseService.createCase.mockResolvedValue({ objectId: 'abc123', status: 'collecting_information' });
    caseService.formatCaseSummary.mockReturnValue({
      caseId: 'abc123',
      status: 'collecting_information',
      extractedCase: {},
      nextQuestion: null,
    });

    const result = await cloudRegistry.mmCreateCase({
      params: { narrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive.' },
    });

    expect(caseService.createCase).toHaveBeenCalledWith({
      narrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive.',
    });
    expect(result.caseId).toBe('abc123');
  });
});

describe('mmAnswerQuestion', () => {
  it('rejects when answer is missing', async () => {
    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'abc123', questionId: 'q1' } })
    ).rejects.toThrow();
    expect(caseService.answerQuestion).not.toHaveBeenCalled();
  });

  it('propagates a not-found error from the service as a Parse error', async () => {
    caseService.answerQuestion.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'missing', questionId: 'q1', answer: 'yes' } })
    ).rejects.toMatchObject({ code: Parse.Error.OBJECT_NOT_FOUND });
  });

  it('propagates a stale-question error as an operation-forbidden Parse error', async () => {
    caseService.answerQuestion.mockRejectedValue(new InvalidStateError('That question is no longer active.'));

    await expect(
      cloudRegistry.mmAnswerQuestion({ params: { caseId: 'abc123', questionId: 'stale', answer: 'yes' } })
    ).rejects.toMatchObject({ code: Parse.Error.OPERATION_FORBIDDEN });
  });

  it('answers a question and returns the summary response', async () => {
    caseService.answerQuestion.mockResolvedValue({ objectId: 'abc123', status: 'ready_to_finalize' });
    caseService.formatCaseSummary.mockReturnValue({
      caseId: 'abc123',
      status: 'ready_to_finalize',
      extractedCase: {},
      nextQuestion: null,
    });

    const result = await cloudRegistry.mmAnswerQuestion({
      params: { caseId: 'abc123', questionId: 'q1', answer: 'About four hours after ICU arrival.' },
    });

    expect(result.status).toBe('ready_to_finalize');
  });
});

describe('mmFinalizeCase', () => {
  it('rejects a missing caseId', async () => {
    await expect(cloudRegistry.mmFinalizeCase({ params: {} })).rejects.toThrow();
    expect(caseService.finalizeCase).not.toHaveBeenCalled();
  });

  it('propagates not-found for a nonexistent case', async () => {
    caseService.finalizeCase.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(cloudRegistry.mmFinalizeCase({ params: { caseId: 'missing' } })).rejects.toMatchObject({
      code: Parse.Error.OBJECT_NOT_FOUND,
    });
  });

  it('finalizes a case and returns the finalized response shape', async () => {
    caseService.finalizeCase.mockResolvedValue({ objectId: 'abc123', status: 'completed' });
    caseService.formatFinalizedCase.mockReturnValue({
      caseId: 'abc123',
      status: 'completed',
      polishedNarrative: 'narrative',
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
    });

    const result = await cloudRegistry.mmFinalizeCase({ params: { caseId: 'abc123' } });

    expect(result.status).toBe('completed');
    expect(result.polishedNarrative).toBe('narrative');
  });
});

describe('mmGetCase', () => {
  it('rejects a missing caseId', async () => {
    await expect(cloudRegistry.mmGetCase({ params: {} })).rejects.toThrow();
    expect(caseService.getCase).not.toHaveBeenCalled();
  });

  it('propagates not-found for a nonexistent case', async () => {
    caseService.getCase.mockRejectedValue(new NotFoundError('No case found with id missing.'));

    await expect(cloudRegistry.mmGetCase({ params: { caseId: 'missing' } })).rejects.toMatchObject({
      code: Parse.Error.OBJECT_NOT_FOUND,
    });
  });

  it('returns the full case state', async () => {
    caseService.getCase.mockResolvedValue({ objectId: 'abc123', status: 'completed' });
    caseService.formatFullCase.mockReturnValue({ caseId: 'abc123', status: 'completed' });

    const result = await cloudRegistry.mmGetCase({ params: { caseId: 'abc123' } });

    expect(result.caseId).toBe('abc123');
  });
});
