jest.mock('../cloud/repositories/caseRepository');
jest.mock('../cloud/repositories/aiCostRepository');
jest.mock('../cloud/ai/caseAnalyzer');
jest.mock('../cloud/ai/questionGenerator');
jest.mock('../cloud/ai/finalizer');
jest.mock('../cloud/ai/facultyQuestionAnswerer');

const caseRepository = require('../cloud/repositories/caseRepository');
const aiCostRepository = require('../cloud/repositories/aiCostRepository');
const caseAnalyzer = require('../cloud/ai/caseAnalyzer');
const questionGenerator = require('../cloud/ai/questionGenerator');
const finalizer = require('../cloud/ai/finalizer');
const facultyQuestionAnswerer = require('../cloud/ai/facultyQuestionAnswerer');
const caseService = require('../cloud/services/caseService');
const { NotFoundError, InvalidStateError, AIProviderError } = require('../cloud/utils/errors');
const { CaseStatus } = require('../cloud/schemas/caseStatus');

function baseCaseState(overrides = {}) {
  return {
    objectId: 'case1',
    ownerId: 'user1',
    status: CaseStatus.COLLECTING_INFORMATION,
    originalNarrative: 'narrative',
    extractedCase: { procedure: 'CABG x3' },
    conversation: [],
    currentQuestion: null,
    polishedNarrative: null,
    discussionPreparation: [],
    likelyFacultyQuestions: [],
    references: [],
    facultyQuestionAnswers: {},
    referenceLookups: {},
    promptVersion: {},
    aiModel: 'gpt-test',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  };
}

afterEach(() => jest.clearAllMocks());

describe('createCase', () => {
  it('asks a follow-up question when the analyzer/question generator says more is needed', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    const created = baseCaseState({ currentQuestion: null });
    caseRepository.create.mockResolvedValue(created);
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: true,
      question: { text: 'How long after surgery did hypotension begin?', category: 'timing', reason: 'Timing matters.' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...created, ...patch }));

    const result = await caseService.createCase({ narrative: 'A 68 year old man...', ownerId: 'user1' });

    expect(result.status).toBe(CaseStatus.COLLECTING_INFORMATION);
    expect(result.currentQuestion.question).toBe('How long after surgery did hypotension begin?');
  });

  it('transitions straight to ready_to_finalize when no question is needed', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    const created = baseCaseState();
    caseRepository.create.mockResolvedValue(created);
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: false,
      question: null,
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...created, ...patch }));

    const result = await caseService.createCase({ narrative: 'A fully detailed narrative...', ownerId: 'user1' });

    expect(result.status).toBe(CaseStatus.READY_TO_FINALIZE);
    expect(result.currentQuestion).toBeNull();
  });

  it('propagates AI provider failures rather than storing a corrupted case', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockRejectedValue(new AIProviderError('AI provider returned status 500.'));

    await expect(caseService.createCase({ narrative: 'narrative', ownerId: 'user1' })).rejects.toThrow(AIProviderError);
    expect(caseRepository.create).not.toHaveBeenCalled();
  });
});

describe('answerQuestion', () => {
  it('throws NotFoundError for an unknown case id', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(
      caseService.answerQuestion({ caseId: 'missing', questionId: 'q1', answer: 'yes', ownerId: 'user1' })
    ).rejects.toThrow(NotFoundError);
  });

  it('throws NotFoundError (not a permission error) when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ ownerId: 'someone-else' }));

    await expect(
      caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: 'yes', ownerId: 'user1' })
    ).rejects.toThrow(NotFoundError);
  });

  it('throws InvalidStateError when the questionId does not match the active question', async () => {
    caseRepository.getById.mockResolvedValue(
      baseCaseState({
        currentQuestion: { questionId: 'q1', question: 'Q?', category: 'timing', reason: 'r', answer: null, askedAt: 'x', answeredAt: null },
      })
    );

    await expect(
      caseService.answerQuestion({ caseId: 'case1', questionId: 'stale-question', answer: 'yes', ownerId: 'user1' })
    ).rejects.toThrow(InvalidStateError);
  });

  it('throws InvalidStateError when the case has no open question', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.READY_TO_FINALIZE, currentQuestion: null }));

    await expect(
      caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: 'yes', ownerId: 'user1' })
    ).rejects.toThrow(InvalidStateError);
  });

  it('incorporates the answer and asks another question when more is needed', async () => {
    const current = baseCaseState({
      currentQuestion: { questionId: 'q1', question: 'How long after surgery?', category: 'timing', reason: 'r', answer: null, askedAt: 'x', answeredAt: null },
    });
    caseRepository.getById.mockResolvedValue(current);
    caseAnalyzer.incorporateAnswer.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3', timing: '4 hours' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...current, ...patch }));
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: true,
      question: { text: 'What was the chest tube output?', category: 'intervention', reason: 'r' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });

    const result = await caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: '4 hours after ICU arrival', ownerId: 'user1' });

    expect(caseAnalyzer.incorporateAnswer).toHaveBeenCalled();
    expect(result.currentQuestion.question).toBe('What was the chest tube output?');
  });

  it('transitions to ready_to_finalize once nothing more is needed', async () => {
    const current = baseCaseState({
      currentQuestion: { questionId: 'q1', question: 'Q?', category: 'timing', reason: 'r', answer: null, askedAt: 'x', answeredAt: null },
    });
    caseRepository.getById.mockResolvedValue(current);
    caseAnalyzer.incorporateAnswer.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...current, ...patch }));
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: false,
      question: null,
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });

    const result = await caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: 'final answer', ownerId: 'user1' });

    expect(result.status).toBe(CaseStatus.READY_TO_FINALIZE);
    expect(result.currentQuestion).toBeNull();
  });
});

describe('finalizeCase', () => {
  it('throws InvalidStateError when the case still has an open question', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.COLLECTING_INFORMATION }));

    await expect(caseService.finalizeCase({ caseId: 'case1', ownerId: 'user1' })).rejects.toThrow(InvalidStateError);
  });

  it('throws InvalidStateError when the case is already completed', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.COMPLETED }));

    await expect(caseService.finalizeCase({ caseId: 'case1', ownerId: 'user1' })).rejects.toThrow(InvalidStateError);
  });

  it('throws NotFoundError for a nonexistent case', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(caseService.finalizeCase({ caseId: 'missing', ownerId: 'user1' })).rejects.toThrow(NotFoundError);
  });

  it('throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.READY_TO_FINALIZE, ownerId: 'someone-else' }));

    await expect(caseService.finalizeCase({ caseId: 'case1', ownerId: 'user1' })).rejects.toThrow(NotFoundError);
  });

  it('generates and persists the finalized case materials', async () => {
    const current = baseCaseState({ status: CaseStatus.READY_TO_FINALIZE });
    caseRepository.getById.mockResolvedValue(current);
    finalizer.finalizeCase.mockResolvedValue({
      polishedNarrative: 'Polished narrative...',
      discussionPreparation: [{ topic: 't', whyItMatters: 'w', prepareToDiscuss: 'p' }],
      likelyFacultyQuestions: ['A question?'],
      references: [{ topic: 't', searchIntent: 's', citation: null, verified: false }],
      meta: { model: 'gpt-test' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...current, ...patch }));

    const result = await caseService.finalizeCase({ caseId: 'case1', ownerId: 'user1' });

    expect(result.status).toBe(CaseStatus.COMPLETED);
    expect(result.polishedNarrative).toBe('Polished narrative...');
    expect(result.references).toHaveLength(1);
  });
});

describe('getCase', () => {
  it('throws NotFoundError for an unknown case id', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(caseService.getCase({ caseId: 'missing', ownerId: 'user1' })).rejects.toThrow(NotFoundError);
  });

  it('throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ ownerId: 'someone-else' }));

    await expect(caseService.getCase({ caseId: 'case1', ownerId: 'user1' })).rejects.toThrow(NotFoundError);
  });

  it('returns the case state for a known id owned by the caller', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState());

    const result = await caseService.getCase({ caseId: 'case1', ownerId: 'user1' });

    expect(result.objectId).toBe('case1');
  });
});

describe('updatePolishedNarrative', () => {
  it('throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(
      baseCaseState({ status: CaseStatus.COMPLETED, ownerId: 'someone-else' })
    );

    await expect(
      caseService.updatePolishedNarrative({ caseId: 'case1', ownerId: 'user1', polishedNarrative: 'Edited narrative text.' })
    ).rejects.toThrow(NotFoundError);
    expect(caseRepository.update).not.toHaveBeenCalled();
  });

  it('throws InvalidStateError when the case has not been finalized yet', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.READY_TO_FINALIZE }));

    await expect(
      caseService.updatePolishedNarrative({ caseId: 'case1', ownerId: 'user1', polishedNarrative: 'Edited narrative text.' })
    ).rejects.toThrow(InvalidStateError);
    expect(caseRepository.update).not.toHaveBeenCalled();
  });

  it('persists the edited narrative for a completed case', async () => {
    const current = baseCaseState({ status: CaseStatus.COMPLETED, polishedNarrative: 'Original narrative.' });
    caseRepository.getById.mockResolvedValue(current);
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...current, ...patch }));

    const result = await caseService.updatePolishedNarrative({
      caseId: 'case1',
      ownerId: 'user1',
      polishedNarrative: 'Edited narrative text.',
    });

    expect(caseRepository.update).toHaveBeenCalledWith('case1', { polishedNarrative: 'Edited narrative text.' });
    expect(result.polishedNarrative).toBe('Edited narrative text.');
  });
});

describe('AI cost tracking', () => {
  it('records usage for both AI calls made during createCase and rolls them into the case total', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-4o', usage: { prompt_tokens: 200, completion_tokens: 50, total_tokens: 250 } },
      promptVersion: '1.0.0',
    });
    const created = baseCaseState({ currentQuestion: null });
    caseRepository.create.mockResolvedValue(created);
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: false,
      question: null,
      meta: { model: 'gpt-4o', usage: { prompt_tokens: 80, completion_tokens: 20, total_tokens: 100 } },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...created, ...patch }));
    aiCostRepository.record.mockResolvedValue({ costUSD: 0.001, totalTokens: 250 });

    await caseService.createCase({ narrative: 'A 68 year old man...', ownerId: 'user1' });

    expect(aiCostRepository.record).toHaveBeenCalledWith(
      expect.objectContaining({ caseId: 'case1', ownerId: 'user1', operation: 'analyzeInitialNarrative' })
    );
    expect(aiCostRepository.record).toHaveBeenCalledWith(
      expect.objectContaining({ caseId: 'case1', ownerId: 'user1', operation: 'generateNextQuestion' })
    );
    expect(caseRepository.incrementAIUsage).toHaveBeenCalledTimes(2);
  });

  it('does not skip recording -- but a recording failure never breaks the case workflow', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-4o', usage: { prompt_tokens: 200, completion_tokens: 50, total_tokens: 250 } },
      promptVersion: '1.0.0',
    });
    const created = baseCaseState({ currentQuestion: null });
    caseRepository.create.mockResolvedValue(created);
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: false,
      question: null,
      meta: { model: 'gpt-4o', usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 } },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...created, ...patch }));
    aiCostRepository.record.mockRejectedValue(new Error('cost table unavailable'));

    const result = await caseService.createCase({ narrative: 'A 68 year old man...', ownerId: 'user1' });

    expect(result.status).toBe(CaseStatus.READY_TO_FINALIZE);
  });

  it('skips recording entirely when the AI call meta has no usage', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockResolvedValue({
      extractedCase: { procedure: 'CABG x3' },
      meta: { model: 'gpt-4o' },
      promptVersion: '1.0.0',
    });
    const created = baseCaseState({ currentQuestion: null });
    caseRepository.create.mockResolvedValue(created);
    questionGenerator.generateNextQuestion.mockResolvedValue({
      needsQuestion: false,
      question: null,
      meta: { model: 'gpt-4o' },
      promptVersion: '1.0.0',
    });
    caseRepository.update.mockImplementation(async (id, patch) => ({ ...created, ...patch }));

    await caseService.createCase({ narrative: 'A 68 year old man...', ownerId: 'user1' });

    expect(aiCostRepository.record).not.toHaveBeenCalled();
    expect(caseRepository.incrementAIUsage).not.toHaveBeenCalled();
  });
});

describe('getCaseAICost', () => {
  it('throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ ownerId: 'someone-else' }));

    await expect(caseService.getCaseAICost({ caseId: 'case1', ownerId: 'user1' })).rejects.toThrow(NotFoundError);
    expect(aiCostRepository.listForCase).not.toHaveBeenCalled();
  });

  it('returns the running total plus the individual recorded calls', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ aiCostUSD: 0.0234, aiTotalTokens: 900 }));
    aiCostRepository.listForCase.mockResolvedValue([
      { objectId: 'ac1', operation: 'analyzeInitialNarrative', model: 'gpt-4o', costUSD: 0.01, totalTokens: 500 },
      { objectId: 'ac2', operation: 'generateNextQuestion', model: 'gpt-4o', costUSD: 0.0134, totalTokens: 400 },
    ]);

    const result = await caseService.getCaseAICost({ caseId: 'case1', ownerId: 'user1' });

    expect(result.totalCostUSD).toBe(0.0234);
    expect(result.totalTokens).toBe(900);
    expect(result.calls).toHaveLength(2);
  });
});

describe('answerFacultyQuestion', () => {
  it('throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ ownerId: 'someone-else' }));

    await expect(
      caseService.answerFacultyQuestion({ caseId: 'case1', ownerId: 'user1', question: 'Why now?' })
    ).rejects.toThrow(NotFoundError);
    expect(facultyQuestionAnswerer.answerQuestion).not.toHaveBeenCalled();
  });

  it('drafts an answer grounded in the case and records AI usage', async () => {
    const state = baseCaseState({
      extractedCase: { procedure: 'CABG x3' },
      conversation: [{ question: 'When?', answer: 'Four hours postop.' }],
      polishedNarrative: 'A 68-year-old man underwent CABG x3...',
    });
    caseRepository.getById.mockResolvedValue(state);
    facultyQuestionAnswerer.answerQuestion.mockResolvedValue({
      answer: 'Imaging was obtained once transfusion requirements began escalating.',
      meta: { model: 'gpt-test', latencyMs: 5, usage: { total_tokens: 40 } },
      promptVersion: '1.0.0',
    });
    aiCostRepository.record.mockResolvedValue({ costUSD: 0.001, totalTokens: 40 });
    caseRepository.incrementAIUsage.mockResolvedValue(undefined);

    const result = await caseService.answerFacultyQuestion({
      caseId: 'case1',
      ownerId: 'user1',
      question: 'What prompted the decision to obtain imaging at that point?',
    });

    expect(facultyQuestionAnswerer.answerQuestion).toHaveBeenCalledWith({
      extractedCase: { procedure: 'CABG x3' },
      conversation: [{ question: 'When?', answer: 'Four hours postop.' }],
      polishedNarrative: 'A 68-year-old man underwent CABG x3...',
      question: 'What prompted the decision to obtain imaging at that point?',
      caseId: 'case1',
    });
    expect(aiCostRepository.record).toHaveBeenCalledWith(
      expect.objectContaining({ caseId: 'case1', ownerId: 'user1', operation: 'answerFacultyQuestion' })
    );
    expect(caseRepository.update).toHaveBeenCalledWith('case1', {
      facultyQuestionAnswers: { 'What prompted the decision to obtain imaging at that point?': 'Imaging was obtained once transfusion requirements began escalating.' },
    });
    expect(result).toEqual({
      question: 'What prompted the decision to obtain imaging at that point?',
      answer: 'Imaging was obtained once transfusion requirements began escalating.',
    });
  });

  it('returns a cached answer with no AI call when this question was already answered', async () => {
    const state = baseCaseState({
      facultyQuestionAnswers: { 'Why now?': 'Because transfusion requirements were escalating.' },
    });
    caseRepository.getById.mockResolvedValue(state);

    const result = await caseService.answerFacultyQuestion({ caseId: 'case1', ownerId: 'user1', question: 'Why now?' });

    expect(facultyQuestionAnswerer.answerQuestion).not.toHaveBeenCalled();
    expect(aiCostRepository.record).not.toHaveBeenCalled();
    expect(caseRepository.update).not.toHaveBeenCalled();
    expect(result).toEqual({ question: 'Why now?', answer: 'Because transfusion requirements were escalating.' });
  });
});

describe('reference lookup caching', () => {
  it('getCachedReferenceLookup returns null when the topic has not been searched before', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState());

    const { cached } = await caseService.getCachedReferenceLookup({ caseId: 'case1', ownerId: 'user1', topic: 'Postoperative bleeding' });

    expect(cached).toBeNull();
  });

  it('getCachedReferenceLookup returns a previously cached lookup for that topic', async () => {
    const cachedLookup = { query: 'postoperative bleeding[tiab]', results: [{ pmid: '111' }], cachedAt: '2026-01-01T00:00:00.000Z' };
    caseRepository.getById.mockResolvedValue(baseCaseState({ referenceLookups: { 'Postoperative bleeding': cachedLookup } }));

    const { cached } = await caseService.getCachedReferenceLookup({ caseId: 'case1', ownerId: 'user1', topic: 'Postoperative bleeding' });

    expect(cached).toEqual(cachedLookup);
  });

  it('getCachedReferenceLookup throws NotFoundError when the case belongs to a different user', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ ownerId: 'someone-else' }));

    await expect(
      caseService.getCachedReferenceLookup({ caseId: 'case1', ownerId: 'user1', topic: 'Postoperative bleeding' })
    ).rejects.toThrow(NotFoundError);
  });

  it('cacheReferenceLookup persists the new lookup alongside any existing ones', async () => {
    await caseService.cacheReferenceLookup({
      caseId: 'case1',
      existingLookups: { 'Other topic': { query: 'q', results: [], cachedAt: 'x' } },
      topic: 'Postoperative bleeding',
      query: 'postoperative bleeding[tiab]',
      results: [{ pmid: '111' }],
    });

    expect(caseRepository.update).toHaveBeenCalledWith('case1', {
      referenceLookups: expect.objectContaining({
        'Other topic': { query: 'q', results: [], cachedAt: 'x' },
        'Postoperative bleeding': expect.objectContaining({
          query: 'postoperative bleeding[tiab]',
          results: [{ pmid: '111' }],
        }),
      }),
    });
  });
});

describe('listCases', () => {
  it('maps each case to a list row with a derived title', async () => {
    const createdAt = new Date('2026-01-01T00:00:00.000Z');
    const updatedAt = new Date('2026-01-02T00:00:00.000Z');
    caseRepository.listForOwner.mockResolvedValue([
      baseCaseState({
        objectId: 'case1',
        originalNarrative: 'A 68-year-old man underwent CABG x3 and later became hypotensive with increasing chest tube output.',
        status: CaseStatus.COMPLETED,
        createdAt,
        updatedAt,
      }),
    ]);

    const result = await caseService.listCases({ ownerId: 'user1' });

    expect(caseRepository.listForOwner).toHaveBeenCalledWith('user1');
    expect(result).toEqual([
      {
        caseId: 'case1',
        title: 'A 68-year-old man underwent CABG x3 and later became hypoten…',
        status: CaseStatus.COMPLETED,
        createdAt,
        updatedAt,
      },
    ]);
  });

  it('returns an empty array when the caller owns no cases', async () => {
    caseRepository.listForOwner.mockResolvedValue([]);

    expect(await caseService.listCases({ ownerId: 'user1' })).toEqual([]);
  });
});

describe('response formatters', () => {
  it('formatCaseSummary maps currentQuestion to the client nextQuestion shape', () => {
    const state = baseCaseState({
      currentQuestion: { questionId: 'q1', question: 'Q text', category: 'timing', reason: 'r', answer: null, askedAt: 'x', answeredAt: null },
    });
    expect(caseService.formatCaseSummary(state)).toEqual({
      caseId: 'case1',
      status: CaseStatus.COLLECTING_INFORMATION,
      extractedCase: { procedure: 'CABG x3' },
      nextQuestion: { id: 'q1', text: 'Q text', category: 'timing', reason: 'r' },
    });
  });

  it('formatFinalizedCase excludes internal fields like promptVersion/aiModel', () => {
    const state = baseCaseState({
      status: CaseStatus.COMPLETED,
      polishedNarrative: 'n',
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
    });
    const formatted = caseService.formatFinalizedCase(state);
    expect(formatted).not.toHaveProperty('promptVersion');
    expect(formatted).not.toHaveProperty('aiModel');
    expect(formatted.caseId).toBe('case1');
  });
});
