const { createFakeParse } = require('./helpers/fakeParse');

const { Parse, store } = createFakeParse();
global.Parse = Parse;

const caseRepository = require('../cloud/repositories/caseRepository');

function baseRecord(overrides = {}) {
  return {
    ownerId: 'user1',
    status: 'collecting_information',
    originalNarrative: 'narrative text',
    extractedCase: { procedure: 'CABG' },
    conversation: [],
    currentQuestion: null,
    polishedNarrative: null,
    discussionPreparation: [],
    likelyFacultyQuestions: [],
    references: [],
    promptVersion: {},
    aiModel: 'gpt-test',
    ...overrides,
  };
}

describe('caseRepository', () => {
  it('creates a case and returns client-facing JSON', async () => {
    const created = await caseRepository.create(baseRecord());

    expect(created.objectId).toBeDefined();
    expect(created.ownerId).toBe('user1');
    expect(created.status).toBe('collecting_information');
    expect(created.extractedCase).toEqual({ procedure: 'CABG' });
    expect(created.createdAt).toBeInstanceOf(Date);
  });

  it('initializes AI cost/token totals to zero', async () => {
    const created = await caseRepository.create(baseRecord());

    expect(created.aiCostUSD).toBe(0);
    expect(created.aiTotalTokens).toBe(0);
  });

  it('incrementAIUsage adds to (not replaces) the running totals across multiple calls', async () => {
    const created = await caseRepository.create(baseRecord());

    await caseRepository.incrementAIUsage(created.objectId, { costUSD: 0.01, totalTokens: 150 });
    await caseRepository.incrementAIUsage(created.objectId, { costUSD: 0.02, totalTokens: 100 });

    const fetched = await caseRepository.getById(created.objectId);
    expect(fetched.aiCostUSD).toBeCloseTo(0.03, 10);
    expect(fetched.aiTotalTokens).toBe(250);
  });

  it('incrementAIUsage advances the token total even when costUSD is null (unpriced model)', async () => {
    const created = await caseRepository.create(baseRecord());

    await caseRepository.incrementAIUsage(created.objectId, { costUSD: null, totalTokens: 75 });

    const fetched = await caseRepository.getById(created.objectId);
    expect(fetched.aiCostUSD).toBe(0);
    expect(fetched.aiTotalTokens).toBe(75);
  });

  it('restricts the saved object ACL to the owning user, with no public access', async () => {
    const created = await caseRepository.create(baseRecord());
    const acl = store.get(created.objectId).acl;

    expect(acl.publicRead).toBe(false);
    expect(acl.publicWrite).toBe(false);
    expect(acl.readAccess.has('user1')).toBe(true);
    expect(acl.writeAccess.has('user1')).toBe(true);
  });

  it('retrieves a previously created case by id', async () => {
    const created = await caseRepository.create(baseRecord());
    const fetched = await caseRepository.getById(created.objectId);

    expect(fetched).not.toBeNull();
    expect(fetched.objectId).toBe(created.objectId);
    expect(fetched.originalNarrative).toBe('narrative text');
  });

  it('returns null for a missing or malformed case id', async () => {
    expect(await caseRepository.getById('does-not-exist')).toBeNull();
  });

  it('updates only the given fields and preserves the rest', async () => {
    const created = await caseRepository.create(baseRecord());
    const updated = await caseRepository.update(created.objectId, { status: 'ready_to_finalize' });

    expect(updated.status).toBe('ready_to_finalize');
    expect(updated.originalNarrative).toBe('narrative text');
    expect(updated.extractedCase).toEqual({ procedure: 'CABG' });
  });

  it('defaults facultyQuestionAnswers and referenceLookups to empty objects', async () => {
    const created = await caseRepository.create(baseRecord());

    expect(created.facultyQuestionAnswers).toEqual({});
    expect(created.referenceLookups).toEqual({});
  });

  describe('listForOwner', () => {
    // Distinct owner ids from every other test in this file -- the fake
    // Parse store is shared module-wide with no reset between tests, and
    // this is the only test that queries broadly by owner rather than by
    // a specific known object id, so it must not collide with the
    // 'user1' cases other tests leave behind in that shared store.
    it('returns only the given owner\'s cases, most recent first', async () => {
      const wait = () => new Promise((resolve) => setTimeout(resolve, 2));

      await caseRepository.create(baseRecord({ ownerId: 'listforowner-user', originalNarrative: 'first' }));
      await wait();
      await caseRepository.create(baseRecord({ ownerId: 'listforowner-other', originalNarrative: 'not this one' }));
      await wait();
      await caseRepository.create(baseRecord({ ownerId: 'listforowner-user', originalNarrative: 'second' }));

      const cases = await caseRepository.listForOwner('listforowner-user');

      expect(cases).toHaveLength(2);
      expect(cases.map((c) => c.originalNarrative)).toEqual(['second', 'first']);
      expect(cases.every((c) => c.ownerId === 'listforowner-user')).toBe(true);
    });

    it('returns an empty array for an owner with no cases', async () => {
      expect(await caseRepository.listForOwner('listforowner-nobody')).toEqual([]);
    });
  });
});
