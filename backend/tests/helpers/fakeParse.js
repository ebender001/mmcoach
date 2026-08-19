/**
 * Minimal in-memory fake of the pieces of the Parse SDK caseRepository.js
 * uses (Parse.Object.extend, Parse.Query#get, Parse.Error, Parse.Cloud).
 * Lets repository/function tests run without the real Parse SDK or network.
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
    constructor() {
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

  class FakeParseQuery {
    async get(id) {
      const obj = store.get(id);
      if (!obj) {
        throw new FakeParseError(FakeParseError.OBJECT_NOT_FOUND, 'Object not found.');
      }
      return obj;
    }
  }

  // Minimal stand-in for a Parse.User pointer -- just enough for
  // caseRepository to attach an `owner` pointer without a real Parse User.
  class FakeParsePointer {
    constructor(id) {
      this.id = id;
      this.className = '_User';
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
    Object: { extend: () => FakeParseObject },
    Query: FakeParseQuery,
    Error: FakeParseError,
    User: { createWithoutData: (id) => new FakeParsePointer(id) },
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
