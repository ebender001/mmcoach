/**
 * Coordinates the M&M case workflow: creating cases, incorporating
 * answers, deciding when to stop asking questions, and finalizing. This is
 * the module Cloud Functions call into -- it delegates extraction/question
 * generation/finalization to ai/*, and persistence to caseRepository.
 */
const caseRepository = require('../repositories/caseRepository');
const aiCostRepository = require('../repositories/aiCostRepository');
const caseAnalyzer = require('../ai/caseAnalyzer');
const questionGenerator = require('../ai/questionGenerator');
const finalizer = require('../ai/finalizer');
const { CaseStatus } = require('../schemas/caseStatus');
const { NotFoundError, InvalidStateError } = require('../utils/errors');
const { generateId } = require('../utils/idGenerator');
const logger = require('../utils/logger');

/**
 * Records one AI provider call's cost/token usage against a case and
 * rolls it into MMCase's running total. A no-op if `meta.usage` is
 * missing (the provider didn't return one) -- callers still get their
 * case update either way, cost tracking is never allowed to block or
 * fail the actual workflow it's observing.
 */
async function recordAIUsage({ caseId, ownerId, operation, meta }) {
  if (!meta || !meta.usage) return;
  try {
    const { costUSD, totalTokens } = await aiCostRepository.record({
      caseId,
      ownerId,
      operation,
      model: meta.model,
      usage: meta.usage,
      latencyMs: meta.latencyMs,
    });
    await caseRepository.incrementAIUsage(caseId, { costUSD, totalTokens });
  } catch (err) {
    logger.error({ module: 'caseService', operation: 'recordAIUsage', caseId, message: err.message });
  }
}

/**
 * Fetches a case and confirms `ownerId` owns it, in one step. A case that
 * exists but belongs to someone else is rejected the same way as one that
 * doesn't exist at all -- a case id alone must never reveal whether it
 * belongs to another user, let alone grant access to it.
 */
async function getOwnedCase(caseId, ownerId) {
  const caseState = await caseRepository.getById(caseId);
  if (!caseState || caseState.ownerId !== ownerId) {
    throw new NotFoundError(`No case found with id ${caseId}.`);
  }
  return caseState;
}

function toNextQuestion(currentQuestion) {
  if (!currentQuestion) return null;
  return {
    id: currentQuestion.questionId,
    text: currentQuestion.question,
    category: currentQuestion.category,
    reason: currentQuestion.reason,
  };
}

/**
 * Runs the question generator against the case's current state and
 * persists either a new currentQuestion (status stays collecting) or a
 * transition to ready_to_finalize.
 */
async function applyQuestionOutcome(caseState, ownerId) {
  const questionResult = await questionGenerator.generateNextQuestion({
    extractedCase: caseState.extractedCase,
    conversation: caseState.conversation,
    caseId: caseState.objectId,
  });
  await recordAIUsage({
    caseId: caseState.objectId,
    ownerId,
    operation: 'generateNextQuestion',
    meta: questionResult.meta,
  });

  const promptVersion = {
    ...caseState.promptVersion,
    question: questionResult.promptVersion,
  };

  let update;
  if (questionResult.needsQuestion) {
    update = {
      status: CaseStatus.COLLECTING_INFORMATION,
      currentQuestion: {
        questionId: generateId('q'),
        question: questionResult.question.text,
        category: questionResult.question.category,
        reason: questionResult.question.reason,
        answer: null,
        askedAt: new Date().toISOString(),
        answeredAt: null,
      },
      promptVersion,
      aiModel: questionResult.meta.model,
    };
  } else {
    update = {
      status: CaseStatus.READY_TO_FINALIZE,
      currentQuestion: null,
      promptVersion,
      aiModel: questionResult.meta.model,
    };
  }

  const saved = await caseRepository.update(caseState.objectId, update);
  logger.info({
    module: 'caseService',
    caseId: saved.objectId,
    operation: 'applyQuestionOutcome',
    status: saved.status,
  });
  return saved;
}

async function createCase({ narrative, ownerId }) {
  const analysis = await caseAnalyzer.analyzeInitialNarrative({ narrative, caseId: 'new' });

  const created = await caseRepository.create({
    ownerId,
    status: CaseStatus.COLLECTING_INFORMATION,
    originalNarrative: narrative,
    extractedCase: analysis.extractedCase,
    conversation: [],
    currentQuestion: null,
    polishedNarrative: null,
    discussionPreparation: [],
    likelyFacultyQuestions: [],
    references: [],
    promptVersion: { analyze: analysis.promptVersion },
    aiModel: analysis.meta.model,
  });
  await recordAIUsage({
    caseId: created.objectId,
    ownerId,
    operation: 'analyzeInitialNarrative',
    meta: analysis.meta,
  });

  return applyQuestionOutcome(created, ownerId);
}

async function answerQuestion({ caseId, questionId, answer, ownerId }) {
  const caseState = await getOwnedCase(caseId, ownerId);
  if (caseState.status !== CaseStatus.COLLECTING_INFORMATION || !caseState.currentQuestion) {
    throw new InvalidStateError('This case is not currently awaiting an answer.');
  }
  if (caseState.currentQuestion.questionId !== questionId) {
    throw new InvalidStateError('That question is no longer the active question for this case.');
  }

  const answeredEntry = {
    ...caseState.currentQuestion,
    answer,
    answeredAt: new Date().toISOString(),
  };
  const conversation = [...caseState.conversation, answeredEntry];

  const incorporation = await caseAnalyzer.incorporateAnswer({
    extractedCase: caseState.extractedCase,
    conversation,
    newEntry: answeredEntry,
    caseId,
  });
  await recordAIUsage({ caseId, ownerId, operation: 'incorporateAnswer', meta: incorporation.meta });

  const updated = await caseRepository.update(caseId, {
    conversation,
    currentQuestion: null,
    extractedCase: incorporation.extractedCase,
    promptVersion: { ...caseState.promptVersion, analyze: incorporation.promptVersion },
    aiModel: incorporation.meta.model,
  });

  return applyQuestionOutcome(updated, ownerId);
}

async function finalizeCase({ caseId, ownerId }) {
  const caseState = await getOwnedCase(caseId, ownerId);
  if (caseState.status === CaseStatus.COLLECTING_INFORMATION) {
    throw new InvalidStateError('This case still has an open question and is not ready to finalize.');
  }
  if (caseState.status === CaseStatus.COMPLETED) {
    throw new InvalidStateError('This case has already been finalized.');
  }

  const result = await finalizer.finalizeCase({
    extractedCase: caseState.extractedCase,
    conversation: caseState.conversation,
    originalNarrative: caseState.originalNarrative,
    caseId,
  });
  await recordAIUsage({ caseId, ownerId, operation: 'finalizeCase', meta: result.meta });

  return caseRepository.update(caseId, {
    status: CaseStatus.COMPLETED,
    polishedNarrative: result.polishedNarrative,
    discussionPreparation: result.discussionPreparation,
    likelyFacultyQuestions: result.likelyFacultyQuestions,
    references: result.references,
    promptVersion: { ...caseState.promptVersion, finalize: result.promptVersion },
    aiModel: result.meta.model,
  });
}

async function getCase({ caseId, ownerId }) {
  return getOwnedCase(caseId, ownerId);
}

/** Per-case AI cost: the running total plus every individual call. */
async function getCaseAICost({ caseId, ownerId }) {
  const caseState = await getOwnedCase(caseId, ownerId);
  const calls = await aiCostRepository.listForCase(caseId);
  return {
    caseId,
    totalCostUSD: caseState.aiCostUSD,
    totalTokens: caseState.aiTotalTokens,
    calls,
  };
}

/** Response shape for mmCreateCase / mmAnswerQuestion. */
function formatCaseSummary(caseState) {
  return {
    caseId: caseState.objectId,
    status: caseState.status,
    extractedCase: caseState.extractedCase,
    nextQuestion: toNextQuestion(caseState.currentQuestion),
  };
}

/** Response shape for mmFinalizeCase. */
function formatFinalizedCase(caseState) {
  return {
    caseId: caseState.objectId,
    status: caseState.status,
    polishedNarrative: caseState.polishedNarrative,
    discussionPreparation: caseState.discussionPreparation,
    likelyFacultyQuestions: caseState.likelyFacultyQuestions,
    references: caseState.references,
  };
}

/** Response shape for mmGetCase -- the full client-facing case state. */
function formatFullCase(caseState) {
  return {
    caseId: caseState.objectId,
    status: caseState.status,
    originalNarrative: caseState.originalNarrative,
    extractedCase: caseState.extractedCase,
    conversation: caseState.conversation,
    nextQuestion: toNextQuestion(caseState.currentQuestion),
    polishedNarrative: caseState.polishedNarrative,
    discussionPreparation: caseState.discussionPreparation,
    likelyFacultyQuestions: caseState.likelyFacultyQuestions,
    references: caseState.references,
    promptVersion: caseState.promptVersion,
    aiModel: caseState.aiModel,
    createdAt: caseState.createdAt,
    updatedAt: caseState.updatedAt,
  };
}

module.exports = {
  createCase,
  answerQuestion,
  finalizeCase,
  getCase,
  getCaseAICost,
  formatCaseSummary,
  formatFinalizedCase,
  formatFullCase,
};
