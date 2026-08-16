jest.mock('../cloud/repositories/caseRepository');
jest.mock('../cloud/ai/caseAnalyzer');
jest.mock('../cloud/ai/questionGenerator');
jest.mock('../cloud/ai/finalizer');

const caseRepository = require('../cloud/repositories/caseRepository');
const caseAnalyzer = require('../cloud/ai/caseAnalyzer');
const questionGenerator = require('../cloud/ai/questionGenerator');
const finalizer = require('../cloud/ai/finalizer');
const caseService = require('../cloud/services/caseService');
const { NotFoundError, InvalidStateError, AIProviderError } = require('../cloud/utils/errors');
const { CaseStatus } = require('../cloud/schemas/caseStatus');

function baseCaseState(overrides = {}) {
  return {
    objectId: 'case1',
    status: CaseStatus.COLLECTING_INFORMATION,
    originalNarrative: 'narrative',
    extractedCase: { procedure: 'CABG x3' },
    conversation: [],
    currentQuestion: null,
    polishedNarrative: null,
    discussionPreparation: [],
    likelyFacultyQuestions: [],
    references: [],
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

    const result = await caseService.createCase({ narrative: 'A 68 year old man...' });

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

    const result = await caseService.createCase({ narrative: 'A fully detailed narrative...' });

    expect(result.status).toBe(CaseStatus.READY_TO_FINALIZE);
    expect(result.currentQuestion).toBeNull();
  });

  it('propagates AI provider failures rather than storing a corrupted case', async () => {
    caseAnalyzer.analyzeInitialNarrative.mockRejectedValue(new AIProviderError('AI provider returned status 500.'));

    await expect(caseService.createCase({ narrative: 'narrative' })).rejects.toThrow(AIProviderError);
    expect(caseRepository.create).not.toHaveBeenCalled();
  });
});

describe('answerQuestion', () => {
  it('throws NotFoundError for an unknown case id', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(
      caseService.answerQuestion({ caseId: 'missing', questionId: 'q1', answer: 'yes' })
    ).rejects.toThrow(NotFoundError);
  });

  it('throws InvalidStateError when the questionId does not match the active question', async () => {
    caseRepository.getById.mockResolvedValue(
      baseCaseState({
        currentQuestion: { questionId: 'q1', question: 'Q?', category: 'timing', reason: 'r', answer: null, askedAt: 'x', answeredAt: null },
      })
    );

    await expect(
      caseService.answerQuestion({ caseId: 'case1', questionId: 'stale-question', answer: 'yes' })
    ).rejects.toThrow(InvalidStateError);
  });

  it('throws InvalidStateError when the case has no open question', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.READY_TO_FINALIZE, currentQuestion: null }));

    await expect(
      caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: 'yes' })
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

    const result = await caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: '4 hours after ICU arrival' });

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

    const result = await caseService.answerQuestion({ caseId: 'case1', questionId: 'q1', answer: 'final answer' });

    expect(result.status).toBe(CaseStatus.READY_TO_FINALIZE);
    expect(result.currentQuestion).toBeNull();
  });
});

describe('finalizeCase', () => {
  it('throws InvalidStateError when the case still has an open question', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.COLLECTING_INFORMATION }));

    await expect(caseService.finalizeCase({ caseId: 'case1' })).rejects.toThrow(InvalidStateError);
  });

  it('throws InvalidStateError when the case is already completed', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState({ status: CaseStatus.COMPLETED }));

    await expect(caseService.finalizeCase({ caseId: 'case1' })).rejects.toThrow(InvalidStateError);
  });

  it('throws NotFoundError for a nonexistent case', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(caseService.finalizeCase({ caseId: 'missing' })).rejects.toThrow(NotFoundError);
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

    const result = await caseService.finalizeCase({ caseId: 'case1' });

    expect(result.status).toBe(CaseStatus.COMPLETED);
    expect(result.polishedNarrative).toBe('Polished narrative...');
    expect(result.references).toHaveLength(1);
  });
});

describe('getCase', () => {
  it('throws NotFoundError for an unknown case id', async () => {
    caseRepository.getById.mockResolvedValue(null);

    await expect(caseService.getCase({ caseId: 'missing' })).rejects.toThrow(NotFoundError);
  });

  it('returns the case state for a known id', async () => {
    caseRepository.getById.mockResolvedValue(baseCaseState());

    const result = await caseService.getCase({ caseId: 'case1' });

    expect(result.objectId).toBe('case1');
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
