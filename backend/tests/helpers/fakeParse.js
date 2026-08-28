/**
 * Minimal in-memory fake of the pieces of the Parse SDK the repositories
 * use (Parse.Object.extend, Parse.Query#get/#find, Parse.Error,
 * Parse.Cloud, Parse.User/ACL pointers). Lets repository/function tests
 * run without the real Parse SDK or network.
 */
function createFakeParse() {
  const store = new Map();
  let nextId = 1;

  class FakeParseError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
      this.name = 'ParseError';
    }
  }
  FakeParseError.OBJECT_NOT_FOUND = 101;
  FakeParseError.VALIDATION_ERROR = 142;
  FakeParseError.OPERATION_FORBIDDEN = 119;
  FakeParseError.INTERNAL_SERVER_ERROR = 1;
  FakeParseError.SCRIPT_FAILED = 141;
  FakeParseError.INVALID_SESSION_TOKEN = 209;

  class FakeParseObject {
    constructor(className) {
      this.className = className;
      this.attributes = {};
      this.id = undefined;
      this.createdAt = undefined;
      this.updatedAt = undefined;
      this.acl = undefined;
    }
    set(key, value) {
      this.attributes[key] = value;
    }
    get(key) {
      return this.attributes[key];
    }
    /** Mirrors real Parse's atomic increment op -- see caseRepository#incrementAIUsage. */
    increment(key, amount) {
      this.attributes[key] = (this.attributes[key] || 0) + amount;
    }
    setACL(acl) {
      this.acl = acl;
    }
    async save() {
      const now = new Date();
      if (!this.id) {
        this.id = String(nextId++);
        this.createdAt = now;
      }
      this.updatedAt = now;
      store.set(this.id, this);
      return this;
    }
  }

  // Minimal stand-in for a Parse pointer (e.g. Parse.User.createWithoutData,
  // or Parse.Object.extend(X).createWithoutData) -- just enough identity
  // (id + className) for repositories to attach/query relations without a
  // real fetch.
  class FakeParsePointer {
    constructor(id, className) {
      this.id = id;
      this.className = className;
    }
  }

  /**
   * Real `Parse.Object.extend(className)` returns a distinct subclass per
   * className; this fake mirrors that closely enough for tests to create
   * objects/pointers of the right class and for queries to filter by it.
   */
  function extend(className) {
    class ScopedParseObject extends FakeParseObject {
      constructor() {
        super(className);
      }
    }
    ScopedParseObject.className = className;
    ScopedParseObject.createWithoutData = (id) => new FakeParsePointer(id, className);
    return ScopedParseObject;
  }

  function matchesValue(stored, queried) {
    if (stored && typeof stored === 'object' && queried && typeof queried === 'object') {
      return stored.id === queried.id;
    }
    return stored === queried;
  }

  class FakeParseQuery {
    constructor(ObjectClass) {
      this.targetClassName = ObjectClass && ObjectClass.className;
      this.conditions = [];
      this.order = null;
      this.limitCount = null;
    }
    equalTo(key, value) {
      this.conditions.push({ key, value });
      return this;
    }
    descending(key) {
      this.order = { key, direction: -1 };
      return this;
    }
    limit(count) {
      this.limitCount = count;
      return this;
    }
    async get(id) {
      const obj = store.get(id);
      if (!obj) {
        throw new FakeParseError(FakeParseError.OBJECT_NOT_FOUND, 'Object not found.');
      }
      return obj;
    }
    async find() {
      let results = Array.from(store.values()).filter(
        (obj) => obj.className === this.targetClassName
      );
      for (const { key, value } of this.conditions) {
        results = results.filter((obj) => matchesValue(obj.get(key), value));
      }
      if (this.order) {
        const { key, direction } = this.order;
        results = [...results].sort((a, b) => (a[key] > b[key] ? 1 : a[key] < b[key] ? -1 : 0) * direction);
      }
      if (typeof this.limitCount === 'number') {
        results = results.slice(0, this.limitCount);
      }
      return results;
    }
  }

  class FakeParseACL {
    constructor() {
      this.publicRead = true;
      this.publicWrite = true;
      this.readAccess = new Set();
      this.writeAccess = new Set();
    }
    setPublicReadAccess(allowed) {
      this.publicRead = allowed;
    }
    setPublicWriteAccess(allowed) {
      this.publicWrite = allowed;
    }
    setReadAccess(userId, allowed) {
      if (allowed) this.readAccess.add(userId);
      else this.readAccess.delete(userId);
    }
    setWriteAccess(userId, allowed) {
      if (allowed) this.writeAccess.add(userId);
      else this.writeAccess.delete(userId);
    }
  }

  const cloudRegistry = {};

  const Parse = {
    Object: { extend },
    Query: FakeParseQuery,
    Error: FakeParseError,
    User: { createWithoutData: (id) => new FakeParsePointer(id, '_User') },
    ACL: FakeParseACL,
    Cloud: {
      // The 3rd `options` arg (e.g. { requireUser: true }) mirrors real
      // Parse Server Cloud Code validators. This fake ignores it -- Cloud
      // Functions under test enforce authentication themselves via
      // `requireAuthenticatedUser`, so tests exercise that explicitly
      // rather than relying on the fake to simulate Parse Server's
      // built-in validator behavior.
      define: (name, handler) => {
        cloudRegistry[name] = handler;
      },
    },
  };

  return { Parse, store, cloudRegistry };
}

module.exports = { createFakeParse };
