# MMCoach Backend

Back4App Parse Cloud Code backend for **MMCoach**, an iOS app that helps
surgical trainees prepare Morbidity & Mortality (M&M) conference cases.

The client dictates a case (speech-to-text happens on-device); the backend
receives text, uses AI to extract structured clinical information, asks
targeted follow-up questions one at a time, and finally generates a
polished M&M presentation with discussion prep, likely faculty questions,
and reference-search topics.

**Back4App owns the case state and AI workflow. The mobile client presents
that workflow to the trainee.** All prompt construction, AI orchestration,
and clinical-workflow logic live here, not in the client.

There is no PHI in this MVP, and no HIPAA-specific handling is implemented.
There is no authentication yet (no Parse User); that's expected to be added
later.

---

## Architecture overview

```text
Cloud Function (functions/*.js)
      -> validates input, calls caseService, formats the response
      v
caseService.js
      -> orchestrates the workflow: create / answer / finalize / get
      v
ai/caseAnalyzer.js | ai/questionGenerator.js | ai/finalizer.js
      -> one AI responsibility each, built from prompts/*, validated by schemas/*
      v
aiService.js
      -> the only module that talks to the AI provider (OpenAI)

repositories/caseRepository.js
      -> the only module that touches Parse.Object / Parse.Query directly
```

Cloud Functions never call the AI provider or touch Parse objects directly.
Prompts live only in `prompts/`. Model/config values live only in
`config/aiConfig.js`. This keeps each concern in exactly one place -- see
"Where do I change X?" below.

### Folder structure

```text
backend/
├── cloud/
│   ├── main.js                        # entry point: registers Cloud Functions only
│   ├── functions/                     # thin Parse.Cloud.define handlers
│   │   ├── createCase.js              # mmCreateCase
│   │   ├── answerQuestion.js          # mmAnswerQuestion
│   │   ├── finalizeCase.js            # mmFinalizeCase
│   │   └── getCase.js                 # mmGetCase
│   ├── services/
│   │   ├── caseService.js             # workflow orchestration
│   │   ├── aiService.js               # OpenAI HTTP call, retries, timeout, JSON parsing
│   │   └── referenceService.js        # reference-topic -> pending-reference shape
│   ├── ai/
│   │   ├── caseAnalyzer.js            # narrative -> extractedCase; answer -> updated extractedCase
│   │   ├── questionGenerator.js       # decides the single next question, or none
│   │   └── finalizer.js               # polished narrative, discussion prep, faculty Qs, reference topics
│   ├── prompts/
│   │   ├── persona.js                 # shared "surgical educator" persona text
│   │   ├── analyzeCasePrompt.js
│   │   ├── nextQuestionPrompt.js
│   │   └── finalizeCasePrompt.js
│   ├── schemas/
│   │   ├── caseStatus.js              # the 3 status values, centralized
│   │   ├── extractedCaseSchema.js     # known extractedCase field names + sanitizer
│   │   └── aiResponseSchemas.js       # validates/sanitizes every AI JSON response
│   ├── repositories/
│   │   └── caseRepository.js          # Parse persistence + Parse -> client JSON mapping
│   ├── utils/
│   │   ├── logger.js
│   │   ├── validation.js
│   │   ├── errors.js                  # AppError subclasses + toParseError()
│   │   └── idGenerator.js
│   └── config/
│       └── aiConfig.js                # model name, timeouts, retries -- from env vars
├── public/                            # static hosting (unrelated to Cloud Code)
├── tests/                             # Jest tests, no network / no live OpenAI calls
├── package.json                       # devDependencies only (jest) -- no runtime deps
├── jest.config.js
└── .env.example
```

### Where do I change X?

| Need to change...                      | Look at...                       |
| --------------------------------------- | --------------------------------- |
| How the next question is selected       | `ai/questionGenerator.js`         |
| The question-selection prompt           | `prompts/nextQuestionPrompt.js`   |
| How Parse persistence works             | `repositories/caseRepository.js`  |
| Final presentation generation           | `ai/finalizer.js`                 |
| Cloud Function parameters/validation    | `functions/*.js`, `utils/validation.js` |
| Model name / timeouts / retries         | `config/aiConfig.js`              |
| Case status values                      | `schemas/caseStatus.js`           |
| What an AI JSON response must contain   | `schemas/aiResponseSchemas.js`    |

---

## Back4App setup

This project uses the classic Back4App Cloud Code layout (`cloud/`,
`public/`), deployed with the Back4App/Parse CLI (`.parse.local` /
`.parse.project` in this directory identify the linked app).

1. **Environment variables** -- in the Back4App dashboard, go to
   **App Settings > Server Settings > Environment Variables** and add:

   | Variable             | Required | Default        | Purpose |
   | --------------------- | -------- | -------------- | ------- |
   | `OPENAI_API_KEY`      | yes      | (none)         | OpenAI API key. Never committed, never sent to the client. |
   | `OPENAI_MODEL`        | no       | `gpt-4o-mini`  | Chat Completions model used for all AI calls. |
   | `OPENAI_TIMEOUT_MS`   | no       | `30000`        | Per-request timeout to the AI provider. |
   | `OPENAI_MAX_RETRIES`  | no       | `2`            | Retries on 429/5xx or transport errors. |

   See `.env.example` for a local-reference copy of these names (Back4App
   does not read that file; it's documentation only).

2. **Class-Level Permissions (CLP)** -- the `MMCase` Parse class is created
   automatically the first time `mmCreateCase` runs (Cloud Code uses the
   master key). Because there is no Parse User auth yet, lock down MMCase's
   CLP in the dashboard so **no direct client REST/SDK access** is allowed
   (no public find/get/create/update/delete) -- only Cloud Code, which uses
   the master key, can read or write it.

3. **No client OpenAI access** -- the client never receives an OpenAI
   credential, never chooses the model, and never supplies its own system
   prompt. All of that is fixed server-side in `config/aiConfig.js` and
   `prompts/`.

### Deploying Cloud Code

With the Back4App CLI installed and this directory linked to your app
(already reflected in `.parse.local` / `.parse.project`):

```bash
cd backend
b4a deploy
```

This uploads `cloud/` and `public/`. `cloud/` currently has **zero runtime
npm dependencies** (only Node's built-in `https`/`crypto` modules are used),
so no `cloud/package.json` is required for deployment. `backend/package.json`
is for local development/testing only (Jest) and is not deployed.

---

## Parse `MMCase` schema

One Parse class, `MMCase`, represents a single case-preparation session.
Parse supplies `objectId`, `createdAt`, `updatedAt` automatically.

| Field                    | Type    | Notes |
| ------------------------- | ------- | ----- |
| `status`                  | String  | One of `collecting_information`, `ready_to_finalize`, `completed`. See `schemas/caseStatus.js`. |
| `originalNarrative`       | String  | The trainee's original dictated text. |
| `extractedCase`           | Object  | Flexible structured case data. Only fields the AI actually populated are present -- see `schemas/extractedCaseSchema.js` for the full list of recognized (not required) fields. |
| `conversation`            | Array   | Follow-up Q&A history. Each entry: `{ questionId, question, category, reason, answer, askedAt, answeredAt }`. |
| `currentQuestion`         | Object\|null | The single active, unanswered question (same shape as a conversation entry, `answer`/`answeredAt` null), or `null` if none is pending. |
| `polishedNarrative`       | String\|null | Generated in `mmFinalizeCase`. |
| `discussionPreparation`   | Array   | `{ topic, whyItMatters, prepareToDiscuss }[]`, generated in `mmFinalizeCase`. |
| `likelyFacultyQuestions`  | Array of String | Generated in `mmFinalizeCase`. |
| `references`              | Array   | `{ topic, searchIntent, citation: null, verified: false }[]`. No citations are fabricated in the MVP. |
| `promptVersion`           | Object  | Tracks which prompt version produced each part of the case, e.g. `{ analyze: "1.0.0", question: "1.0.0", finalize: "1.0.0" }`. |
| `aiModel`                 | String\|null | The model name used for the most recent AI call on this case. |

---

## Cloud Functions

All four functions are namespaced with an `mm` prefix.

### `mmCreateCase`

**Params:** `{ narrative: string }` (must be non-empty and reasonably
descriptive; a bare few words is rejected).

**Behavior:** stores the narrative, extracts structured case information,
and either asks one follow-up question or determines the case is already
`ready_to_finalize`.

**Response:**

```json
{
  "caseId": "abc123",
  "status": "collecting_information",
  "extractedCase": { "procedure": "CABG x3", "...": "..." },
  "nextQuestion": {
    "id": "q1",
    "text": "Approximately how long after arrival in the ICU did the hypotension begin?",
    "category": "timing",
    "reason": "Timing is important for understanding the likely cause."
  }
}
```

If nothing further is needed, `status` is `"ready_to_finalize"` and
`nextQuestion` is `null`.

### `mmAnswerQuestion`

**Params:** `{ caseId: string, questionId: string, answer: string }`.
`questionId` must match the case's current active question -- answering a
stale or already-answered question is rejected.

**Behavior:** records the answer, incorporates it into `extractedCase`, and
either asks one more question or transitions to `ready_to_finalize`.

**Response:** same shape as `mmCreateCase`'s response.

### `mmFinalizeCase`

**Params:** `{ caseId: string }`. The case must not still be
`collecting_information` (an open question pending) or already `completed`.

**Behavior:** generates the polished narrative, discussion-prep topics,
likely faculty questions, and pending reference topics; sets
`status = "completed"`.

**Response:**

```json
{
  "caseId": "abc123",
  "status": "completed",
  "polishedNarrative": "A 68-year-old man underwent CABG x3...",
  "discussionPreparation": [
    {
      "topic": "Timing of re-exploration",
      "whyItMatters": "The patient had persistent bleeding with increasing transfusion requirements.",
      "prepareToDiscuss": "Be prepared to discuss thresholds used for re-exploration."
    }
  ],
  "likelyFacultyQuestions": [
    "What made you decide to obtain the CT scan at that point?"
  ],
  "references": [
    {
      "topic": "Postoperative bleeding after cardiac surgery",
      "searchIntent": "Guidelines or high-quality evidence on timing of surgical re-exploration.",
      "citation": null,
      "verified": false
    }
  ]
}
```

### `mmGetCase`

**Params:** `{ caseId: string }`.

**Response:** the full client-facing case state (original narrative,
extractedCase, conversation history, currentQuestion/nextQuestion,
finalized materials once present, promptVersion, aiModel, timestamps). Raw
AI provider responses are never included.

### Errors

All functions reject with a `Parse.Error` (no stack traces, no internal
details):

| Situation                                   | Parse.Error code |
| --------------------------------------------- | ----------------- |
| Missing/empty/too-short input                 | `VALIDATION_ERROR` |
| Case not found (including malformed caseId)   | `OBJECT_NOT_FOUND` |
| Stale question, already-completed, still collecting | `OPERATION_FORBIDDEN` |
| AI provider or AI response problem            | `INTERNAL_SERVER_ERROR` |

---

## AI module responsibilities

- **`ai/caseAnalyzer.js`** -- interprets the initial narrative into
  `extractedCase`, and later merges each new answer into it. Does not
  decide whether to ask another question, and does not write the final
  presentation.
- **`ai/questionGenerator.js`** -- looks at `extractedCase` and the
  conversation so far and returns either `{ needsQuestion: false, question:
  null }` or `{ needsQuestion: true, question: { text, category, reason }
  }`. Never returns more than one question. Instructed to stop once a
  presentable, coherent case can be reconstructed -- not to keep digging for
  hypothetically-available detail.
- **`ai/finalizer.js`** -- generates the polished oral-presentation
  narrative, discussion-prep topics, faculty questions, and reference
  *topics* (never fabricated citations). Delegates the pending-reference
  shape to `services/referenceService.js`.

Every AI call goes through `services/aiService.js`, the single place that
knows how to reach OpenAI (model, timeout, retries, JSON-mode, latency
logging). Every AI JSON response is validated by
`schemas/aiResponseSchemas.js` before it is trusted -- malformed, empty, or
wrong-shaped output raises `AIResponseError` rather than being stored.

### Prompt locations & versioning

Prompts live only in `prompts/`. Each prompt module exports a
`*_PROMPT_VERSION` string; `caseService.js` records which version produced
each part of a case in `MMCase.promptVersion`, so prompt behavior changes
can be evaluated later.

- `prompts/persona.js` -- shared "surgical educator" voice, imported by the
  other three so it's defined once.
- `prompts/analyzeCasePrompt.js` -- initial extraction + answer incorporation.
- `prompts/nextQuestionPrompt.js` -- next-question decision.
- `prompts/finalizeCasePrompt.js` -- final presentation materials.

### References (future work)

`services/referenceService.js` converts AI-identified reference *topics*
into pending reference entries (`citation: null, verified: false`). Actual
literature retrieval/verification (e.g. PubMed) is intentionally not
implemented in this MVP -- `retrieveAndVerifyReferences()` is a documented
no-op placeholder so that feature has an obvious home later.

---

## Testing

```bash
cd backend
npm install
npm test        # runs the Jest suite
npm run lint     # node --check syntax validation on every cloud/*.js file
```

No test depends on a live OpenAI call or a real Parse server:

- **`ai/*` modules** are tested by mocking `services/aiService.js`
  (`jest.mock('../cloud/services/aiService')`), so prompt/validation logic
  is exercised without any network access.
- **`services/aiService.js`** itself is tested by mocking Node's built-in
  `https` module (`jest.mock('https')`), covering success, non-2xx status,
  malformed content JSON, and missing API key -- still no real network call.
- **`services/caseService.js`** is tested by mocking
  `repositories/caseRepository.js` and the three `ai/*` modules, covering:
  creating a case (question needed / not needed), answering a question
  (happy path, stale questionId, no open question), finalizing (happy
  path, still collecting, already completed, not found), retrieving a
  case, and an AI provider failure during creation.
- **`repositories/caseRepository.js`** is tested against a small in-memory
  fake of the Parse SDK (`tests/helpers/fakeParse.js`) rather than a real
  Parse Server.
- **Cloud Function handlers** (`functions/*.js`) are tested with the same
  fake `Parse.Cloud.define`/`Parse.Error`, plus a mocked `caseService`, to
  confirm input validation and Parse-error mapping without touching
  business logic twice.

### Mocking AI calls during development

To develop against the workflow without spending OpenAI credits, mock
`services/aiService.completeJSON` (see any file under `tests/` for the
pattern) so `ai/caseAnalyzer.js`, `ai/questionGenerator.js`, and
`ai/finalizer.js` return canned responses. Because `aiService.js` is the
only module that performs the actual HTTP call, this is the single mock
point needed for any higher-level test or local script.

---

## Example workflow

```text
1. mmCreateCase    { narrative: "A 68-year-old man underwent CABG x3..." }
   -> { caseId, status: "collecting_information", nextQuestion: {...} }

2. mmAnswerQuestion { caseId, questionId: nextQuestion.id, answer: "..." }
   -> { caseId, status: "collecting_information", nextQuestion: {...} }
      ...repeat until...
   -> { caseId, status: "ready_to_finalize", nextQuestion: null }

3. mmFinalizeCase  { caseId }
   -> { caseId, status: "completed", polishedNarrative, discussionPreparation,
        likelyFacultyQuestions, references }

4. mmGetCase       { caseId }
   -> full case state, any time
```

### Example curl calls (REST API)

Replace `YOUR_APP_ID` / `YOUR_JS_KEY` with your Back4App app's values.

```bash
curl -X POST \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-JavaScript-Key: YOUR_JS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"narrative": "A 68-year-old man underwent CABG x3. He was initially stable but several hours later became hypotensive with increasing chest tube output. He received blood products and eventually returned to the operating room."}' \
  https://parseapi.back4app.com/functions/mmCreateCase

curl -X POST \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-JavaScript-Key: YOUR_JS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"caseId": "abc123", "questionId": "q1", "answer": "About four hours after ICU arrival."}' \
  https://parseapi.back4app.com/functions/mmAnswerQuestion

curl -X POST \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-JavaScript-Key: YOUR_JS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"caseId": "abc123"}' \
  https://parseapi.back4app.com/functions/mmFinalizeCase

curl -X POST \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-JavaScript-Key: YOUR_JS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"caseId": "abc123"}' \
  https://parseapi.back4app.com/functions/mmGetCase
```
