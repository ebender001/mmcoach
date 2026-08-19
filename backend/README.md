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

Every case belongs to an authenticated `Parse.User` (email/password or Sign
in with Apple). Cloud Functions resolve the owner from the caller's session
(`request.user`) -- never from a client-supplied id -- and reject access to
a case that exists but belongs to someone else the same way as one that
doesn't exist at all. See "Authentication" below.

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
│   │   ├── getCase.js                 # mmGetCase
│   │   ├── updatePolishedNarrative.js # mmUpdatePolishedNarrative
│   │   ├── getCaseAICost.js           # mmGetCaseAICost
│   │   └── findReferences.js          # mmFindReferences
│   ├── services/
│   │   ├── caseService.js             # workflow orchestration
│   │   ├── aiService.js               # OpenAI HTTP call, retries, timeout, JSON parsing
│   │   ├── referenceService.js        # reference-topic -> pending-reference shape
│   │   └── pubmedService.js           # NCBI E-utilities search + MEDLINE parsing
│   ├── ai/
│   │   ├── caseAnalyzer.js            # narrative -> extractedCase; answer -> updated extractedCase
│   │   ├── questionGenerator.js       # decides the single next question, or none
│   │   ├── finalizer.js               # polished narrative, discussion prep, faculty Qs, reference topics
│   │   └── referenceQueryBuilder.js   # topic + searchIntent -> one well-formed PubMed query
│   ├── prompts/
│   │   ├── persona.js                 # shared "surgical educator" persona text
│   │   ├── analyzeCasePrompt.js
│   │   ├── nextQuestionPrompt.js
│   │   ├── finalizeCasePrompt.js
│   │   └── referenceQueryPrompt.js
│   ├── schemas/
│   │   ├── caseStatus.js              # the 3 status values, centralized
│   │   ├── extractedCaseSchema.js     # known extractedCase field names + sanitizer
│   │   └── aiResponseSchemas.js       # validates/sanitizes every AI JSON response
│   ├── repositories/
│   │   ├── caseRepository.js          # MMCase Parse persistence + Parse -> client JSON mapping
│   │   └── aiCostRepository.js        # MMCaseAICost Parse persistence (per-call AI cost/token log)
│   ├── utils/
│   │   ├── logger.js
│   │   ├── validation.js
│   │   ├── errors.js                  # AppError subclasses + toParseError()
│   │   └── idGenerator.js
│   └── config/
│       ├── aiConfig.js                # model name, timeouts, retries -- from env vars
│       └── aiPricing.js               # USD-per-token pricing table used to cost each AI call
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
| AI cost pricing / which models are priced | `config/aiPricing.js`           |
| How a reference topic becomes a PubMed query | `ai/referenceQueryBuilder.js`, `prompts/referenceQueryPrompt.js` |
| How AI cost is recorded per case        | `repositories/aiCostRepository.js`, `services/caseService.js#recordAIUsage` |
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
   | `OPENAI_MODEL`        | no       | `gpt-4o`  | Chat Completions model used for all AI calls. |
   | `OPENAI_TIMEOUT_MS`   | no       | `30000`        | Per-request timeout to the AI provider. |
   | `OPENAI_MAX_RETRIES`  | no       | `2`            | Retries on 429/5xx or transport errors. |
   | `PUBMED_API_KEY`      | no       | (none)         | NCBI E-utilities API key -- raises the rate limit from 3 to 10 requests/sec. Not required for MMCoach's usage pattern (one search per reference lookup). |
   | `PUBMED_CONTACT_EMAIL`| no       | (none)         | Sent as courtesy identification (`tool`/`email` params) per NCBI's usage guidelines. Omitted entirely if not set -- never fabricated. |

   See `.env.example` for a local-reference copy of these names (Back4App
   does not read that file; it's documentation only).

2. **Class-Level Permissions (CLP)** -- `MMCase` and `MMCaseAICost` are
   both created automatically the first time they're written (Cloud Code
   uses the master key). Lock down both classes' CLP in the dashboard so
   **no direct client REST/SDK access** is allowed (no public find/get/
   create/update/delete) -- only Cloud Code, which uses the master key,
   can read or write them. Per-object ACLs (see "Authentication" below)
   are defense-in-depth for if this is ever loosened, not a substitute
   for it.

3. **No client OpenAI access** -- the client never receives an OpenAI
   credential, never chooses the model, and never supplies its own system
   prompt. All of that is fixed server-side in `config/aiConfig.js` and
   `prompts/`.

4. **Sign in with Apple** -- in the Back4App dashboard, go to **App
   Settings > Server Settings > Sign In With Apple** (Parse Server's
   built-in Apple auth adapter) and enable it with this app's **Bundle
   ID** (`dev.benderapps.MMCoach`) as the client id. No client secret is
   needed for sign-in-token verification -- Parse Server validates the
   identity token's signature against Apple's public keys and checks the
   `aud`/`iss` claims itself. This must be configured before
   `ParseUser.apple.login(...)` (see `AppleSignInService`/
   `ParseAuthenticationService` in the iOS app) will succeed; until it is,
   Apple sign-in attempts fail server-side with an auth-adapter error.

5. **Email verification** (optional but recommended before release) -- in
   **App Settings > Email Settings**, enable "Verify User Emails" and
   configure the sender. Parse Server then emails a verification link on
   signup automatically and populates `emailVerified` on the `Parse.User`
   -- no Cloud Code changes are needed for this.

6. **Password reset email** -- also configured under **App Settings >
   Email Settings**; Back4App provides a default password-reset email
   template. `ParseUser.passwordReset(email:)` (called from
   `ParseAuthenticationService`) uses this directly -- there is no custom
   password-reset Cloud Function.

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

## Authentication

Accounts are plain `Parse.User` records -- there is no custom Cloud Code
for signup/login/password-reset; the iOS client calls `ParseUser` directly
(via `ParseAuthenticationService`, see the iOS app's `Services/`). Cloud
Code's only job is to *consume* the resulting session, never to issue one.

- **Email/password** -- `username` is set to the account's email at
  signup, so Parse's built-in uniqueness and password rules apply as-is.
- **Sign in with Apple** -- uses Parse Server's built-in Apple auth
  adapter via `ParseUser.apple.login(user:identityToken:)` (part of the
  `ParseSwift` package already in this project, no extra SDK). Requires
  the dashboard configuration in step 4 above; see "Remaining backend
  work" below for current status.
- **Session persistence** -- ParseSwift caches the session token/current
  user in the Keychain automatically; every subsequent `BackendService`
  call (including Cloud Function calls) carries that session token, which
  is how `request.user` is populated for `requireAuthenticatedUser`
  below. No app code manages this manually.

### Ownership enforcement

Every `MMCase`-touching Cloud Function (`mmCreateCase`, `mmAnswerQuestion`,
`mmFinalizeCase`, `mmGetCase`) is defined with `{ requireUser: true }`
*and* independently calls `utils/validation.js#requireAuthenticatedUser`,
which reads `request.user.id` -- never a client param -- as the owner. See
`services/caseService.js#getOwnedCase`: it fetches a case and rejects
(`NotFoundError`) unless `caseState.ownerId` matches the caller, so a
case id alone never grants access to someone else's case, and a
wrong-owner case is indistinguishable from a nonexistent one.

`repositories/caseRepository.js` also sets a per-object ACL (read/write
restricted to the owning user, no public access) when a case is created.
Cloud Code uses the master key and therefore never actually relies on this
ACL for its own access -- it's defense-in-depth for if `MMCase`'s CLP is
ever loosened to allow direct client reads.

### Remaining backend work before Sign in with Apple works end-to-end

The iOS client and this Cloud Code are both ready to *use* Sign in with
Apple, but nothing in this repo can complete the following -- they require
dashboard/portal access this codebase can't configure on its own:

1. Enable the Sign In With Apple capability for this app's App ID in the
   Apple Developer portal, and add the corresponding entitlement/
   provisioning profile for the Xcode target (see the iOS deliverables
   section for what's already scaffolded there).
2. Enable and configure Back4App's Apple auth adapter (step 4 above) with
   this app's bundle id.
3. Optionally enable email verification and confirm the password-reset
   email template/sender (steps 5-6 above) before shipping.

Until (2) is done, `ParseUser.apple.login` will fail server-side with an
auth-adapter configuration error -- `AppleSignInService`/
`ParseAuthenticationService` surface that as a normal sign-in failure, not
a crash.

---

## Parse `MMCase` schema

One Parse class, `MMCase`, represents a single case-preparation session.
Parse supplies `objectId`, `createdAt`, `updatedAt` automatically.

| Field                    | Type    | Notes |
| ------------------------- | ------- | ----- |
| `owner`                   | Pointer\<`_User`\> | Set once at creation from `request.user`, never from a client param. Every Cloud Function that reads or mutates a case checks this against the caller before doing so. |
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
| `aiCostUSD`                | Number  | Running total across every AI call made for this case, in USD. `0` for a call whose model isn't in `config/aiPricing.js` (unpriced calls still count toward `aiTotalTokens`). See "AI cost tracking" below. |
| `aiTotalTokens`            | Number  | Running total prompt+completion tokens across every AI call made for this case. |

---

## AI cost tracking

Every AI provider call already returns a token `usage` object (see
`services/aiService.js`); `services/caseService.js#recordAIUsage` turns
that into an estimated dollar cost (`config/aiPricing.js`) and persists
it two ways:

1. **`MMCaseAICost`** -- one row per AI call, so cost is auditable per
   operation, not just visible as a total. See schema below.
2. **`MMCase.aiCostUSD` / `MMCase.aiTotalTokens`** -- a running total on
   the case itself (`repositories/caseRepository.js#incrementAIUsage`,
   using Parse's atomic `increment()` so concurrent calls for the same
   case can't clobber each other), so reading the total doesn't require
   summing the per-call rows.

Recording never blocks or fails the actual case workflow: if
`aiCostRepository.record`/`incrementAIUsage` throws (or the call's model
isn't in the pricing table), the error is logged and swallowed --
`mmCreateCase`/`mmAnswerQuestion`/`mmFinalizeCase` still succeed
normally. `mmCorrectDictation` (dictation-time terminology correction)
is **not** tracked here -- it isn't reliably tied to a case id (it can
run before a case exists, during the initial dictation), so its usage
isn't currently recorded anywhere.

### Parse `MMCaseAICost` schema

One row per AI provider call. Parse supplies `objectId`/`createdAt`
automatically (`updatedAt` is unused -- rows are never modified after
creation).

| Field               | Type    | Notes |
| -------------------- | ------- | ----- |
| `case`                | Pointer\<`MMCase`\> | The case this call was made for. |
| `owner`               | Pointer\<`_User`\> | Same owner as the case, set from `request.user`. |
| `operation`           | String  | Which AI call this was: `analyzeInitialNarrative`, `incorporateAnswer`, `generateNextQuestion`, or `finalizeCase`. |
| `model`               | String  | The OpenAI model used (`config/aiConfig.js#getModel`). |
| `promptTokens` / `completionTokens` / `totalTokens` | Number | From the provider's `usage` object. |
| `costUSD`             | Number\|null | `null` when `model` isn't in `config/aiPricing.js` -- never a guessed number. |
| `latencyMs`           | Number\|null | The AI call's round-trip time. |

Like `MMCase`, this class should have its CLP locked to Cloud-Code-only
access (no direct client REST/SDK access) -- see "Back4App setup" above.
Its per-object ACL restricts read/write to the owning user as
defense-in-depth, for the same reason `MMCase`'s does.

---

## Cloud Functions

All functions are namespaced with an `mm` prefix.

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

### `mmUpdatePolishedNarrative`

**Params:** `{ caseId: string, polishedNarrative: string }` (same
non-empty/reasonable-length check as `mmCreateCase`'s narrative).

**Behavior:** overwrites the polished narrative on an already-`completed`
case -- lets the trainee hand-fix a phrasing issue after finalization.
Rejected (`OPERATION_FORBIDDEN`) if the case isn't `completed` yet.
Does **not** regenerate `discussionPreparation`/`likelyFacultyQuestions`/
`references` -- those still reflect the AI's original version of the
narrative.

**Response:** same shape as `mmFinalizeCase`.

### `mmGetCaseAICost`

**Params:** `{ caseId: string }`.

**Behavior:** returns the case's running AI cost/token total plus every
individually recorded AI call. See "AI cost tracking" above.

**Response:**

```json
{
  "caseId": "abc123",
  "totalCostUSD": 0.0234,
  "totalTokens": 1850,
  "calls": [
    {
      "objectId": "xyz1",
      "operation": "analyzeInitialNarrative",
      "model": "gpt-4o",
      "promptTokens": 620,
      "completionTokens": 140,
      "totalTokens": 760,
      "costUSD": 0.0029,
      "latencyMs": 842,
      "createdAt": "2026-08-19T14:02:11.000Z"
    }
  ]
}
```

### `mmFindReferences`

**Params:** `{ topic: string, searchIntent?: string, caseId?: string }`.
`caseId` is optional but the iOS client always sends it: when present,
it's used to verify the caller owns that case (same `OBJECT_NOT_FOUND`
behavior as every other case-scoped function) and to roll this call's AI
cost into that case's running total (see "AI cost tracking"). This
function reads a case only to check ownership -- it never writes
anything onto one.

**Behavior:** first asks the AI to translate `topic` + `searchIntent`
into one well-formed PubMed query (`ai/referenceQueryBuilder.js` --
MeSH headings and title/abstract keywords, boolean AND across 2-4
concepts, biased toward reviews/guidelines over case reports) rather
than sending the raw topic phrase straight to PubMed's own automatic
term mapping. Then searches PubMed with that query (NCBI E-utilities:
`esearch` for the top-5 most relevant PMIDs, `efetch` in MEDLINE format
for title/authors/journal/year/abstract -- see `services/pubmedService.js`).
If the AI-crafted query returns nothing (it can occasionally
over-constrain), retries once with the plain `topic` before giving up.
`results` is `[]` if nothing matches either way, and no citation is ever
fabricated. Each result's abstract is split into `{ label, text }`
sections wherever the source has NLM's structured-abstract labels
(Background/Methods/Results/Conclusions, etc. -- see
`pubmedService.js#splitAbstractSections`); an unstructured abstract comes
back as a single section with `label: null`.

**Response:**

```json
{
  "topic": "Postoperative bleeding after cardiac surgery",
  "results": [
    {
      "pmid": "12345678",
      "title": "Timing of surgical re-exploration after cardiac surgery",
      "authors": ["Smith J", "Doe A"],
      "journal": "J Thorac Cardiovasc Surg",
      "year": "2019",
      "abstractSections": [
        { "label": "Background", "text": "..." },
        { "label": "Methods", "text": "..." },
        { "label": "Results", "text": "..." },
        { "label": "Conclusions", "text": "..." }
      ],
      "url": "https://pubmed.ncbi.nlm.nih.gov/12345678/"
    }
  ]
}
```

### Errors

All functions reject with a `Parse.Error` (no stack traces, no internal
details):

| Situation                                   | Parse.Error code |
| --------------------------------------------- | ----------------- |
| No signed-in user (missing/invalid session)   | `INVALID_SESSION_TOKEN` |
| Missing/empty/too-short input                 | `VALIDATION_ERROR` |
| Case not found, malformed caseId, **or case belongs to a different user** | `OBJECT_NOT_FOUND` |
| Stale question, already-completed, still collecting | `OPERATION_FORBIDDEN` |
| AI provider/response problem, or PubMed unreachable/unparseable | `INTERNAL_SERVER_ERROR` |

A case owned by another user is reported identically to a case that
doesn't exist (`OBJECT_NOT_FOUND`) -- a valid caseId alone must never
confirm that a case exists if the caller doesn't own it.

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

### References

`services/referenceService.js` converts AI-identified reference *topics*
into pending reference entries (`citation: null, verified: false`) at
finalize time. That part is still deliberately unverified/unfetched --
`retrieveAndVerifyReferences()` remains a no-op placeholder, since
auto-populating a citation without the trainee seeing/choosing it risks
presenting an AI-selected source as authoritative.

What *is* implemented: an **on-demand** PubMed lookup per topic
(`mmFindReferences`, see above) -- tapping a reference card in the iOS
app searches PubMed live for that topic and shows candidate articles
with abstracts, so the trainee reviews and picks their own sources rather
than the app silently attaching one. This is intentionally a read-only
lookup: results aren't written back onto `MMCase.references`.

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
