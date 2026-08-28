const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, store } = createFakeParse();
global.Parse = Parse;

const aiCostRepository = require('../cloud/repositories/aiCostRepository');
const caseRepository = require('../cloud/repositories/caseRepository');

describe('aiCostRepository.record', () => {
  it('computes cost for a priced model and stores token counts', async () => {
    const { costUSD, totalTokens } = await aiCostRepository.record({
      caseId: 'case1',
      ownerId: 'user1',
      operation: 'analyzeInitialNarrative',
      model: 'gpt-4o',
      usage: { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 },
      latencyMs: 842,
    });

    // gpt-4o: $2.50 / 1M input, $10.00 / 1M output (see config/aiPricing.js)
    expect(costUSD).toBeCloseTo(1000 / 1_000_000 * 2.5 + 500 / 1_000_000 * 10, 10);
    expect(totalTokens).toBe(1500);
  });

  it('returns a null cost for an unpriced model without throwing', async () => {
    const { costUSD, totalTokens } = await aiCostRepository.record({
      caseId: 'case1',
      ownerId: 'user1',
      operation: 'finalizeCase',
      model: 'some-future-model',
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    });

    expect(costUSD).toBeNull();
    expect(totalTokens).toBe(150);
  });

  it('restricts the saved row ACL to the owning user, with no public access', async () => {
    await aiCostRepository.record({
      caseId: 'case1',
      ownerId: 'user1',
      operation: 'finalizeCase',
      model: 'gpt-4o',
      usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
    });

    const row = Array.from(store.values())
      .filter((obj) => obj.className === aiCostRepository.CLASS_NAME)
      .pop();

    expect(row.acl.publicRead).toBe(false);
    expect(row.acl.publicWrite).toBe(false);
    expect(row.acl.readAccess.has('user1')).toBe(true);
    expect(row.acl.writeAccess.has('user1')).toBe(true);
  });
});

describe('aiCostRepository.listForCase', () => {
  it('returns only the rows for the given case, most recent first', async () => {
    const created = await caseRepository.create({
      ownerId: 'user2',
      status: 'collecting_information',
      originalNarrative: 'narrative',
      extractedCase: {},
      conversation: [],
      currentQuestion: null,
      polishedNarrative: null,
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
      promptVersion: {},
      aiModel: null,
    });
    const otherCase = await caseRepository.create({
      ownerId: 'user2',
      status: 'collecting_information',
      originalNarrative: 'other narrative',
      extractedCase: {},
      conversation: [],
      currentQuestion: null,
      polishedNarrative: null,
      discussionPreparation: [],
      likelyFacultyQuestions: [],
      references: [],
      promptVersion: {},
      aiModel: null,
    });

    await aiCostRepository.record({
      caseId: created.objectId,
      ownerId: 'user2',
      operation: 'analyzeInitialNarrative',
      model: 'gpt-4o',
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    });
    await aiCostRepository.record({
      caseId: created.objectId,
      ownerId: 'user2',
      operation: 'generateNextQuestion',
      model: 'gpt-4o',
      usage: { prompt_tokens: 80, completion_tokens: 20, total_tokens: 100 },
    });
    await aiCostRepository.record({
      caseId: otherCase.objectId,
      ownerId: 'user2',
      operation: 'analyzeInitialNarrative',
      model: 'gpt-4o',
      usage: { prompt_tokens: 999, completion_tokens: 999, total_tokens: 1998 },
    });

    const rows = await aiCostRepository.listForCase(created.objectId);

    expect(rows).toHaveLength(2);
    expect(rows.map((row) => row.operation).sort()).toEqual(
      ['analyzeInitialNarrative', 'generateNextQuestion'].sort()
    );
  });
});

describe('aiCostRepository.listAll', () => {
  it('returns rows across every owner, oldest first', async () => {
    await aiCostRepository.record({
      caseId: 'caseA',
      ownerId: 'userA',
      operation: 'analyzeInitialNarrative',
      model: 'gpt-4o',
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    });
    await aiCostRepository.record({
      caseId: 'caseB',
      ownerId: 'userB',
      operation: 'finalizeCase',
      model: 'gpt-4o-mini',
      usage: { prompt_tokens: 200, completion_tokens: 100, total_tokens: 300 },
    });

    const rows = await aiCostRepository.listAll();

    expect(rows.map((row) => row.ownerId)).toEqual(expect.arrayContaining(['userA', 'userB']));
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i].createdAt.getTime()).toBeGreaterThanOrEqual(rows[i - 1].createdAt.getTime());
    }
    expect(rows.every((row) => row.objectId)).toBe(true);
  });

  it('excludes rows created before sinceDate', async () => {
    await aiCostRepository.record({
      caseId: 'caseC',
      ownerId: 'userC',
      operation: 'finalizeCase',
      model: 'gpt-4o',
      usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
    });

    const future = new Date(Date.now() + 60_000);
    const rows = await aiCostRepository.listAll({ sinceDate: future });

    expect(rows).toHaveLength(0);
  });
});
