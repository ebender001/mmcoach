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

  class FakeParseObject {
    constructor() {
      this.attributes = {};
      this.id = undefined;
      this.createdAt = undefined;
      this.updatedAt = undefined;
    }
    set(key, value) {
      this.attributes[key] = value;
    }
    get(key) {
      return this.attributes[key];
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

  const cloudRegistry = {};

  const Parse = {
    Object: { extend: () => FakeParseObject },
    Query: FakeParseQuery,
    Error: FakeParseError,
    Cloud: {
      define: (name, handler) => {
        cloudRegistry[name] = handler;
      },
    },
  };

  return { Parse, store, cloudRegistry };
}

module.exports = { createFakeParse };
