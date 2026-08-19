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
});
