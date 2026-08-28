/**
 * Cloud Code entry point. This file only registers Cloud Functions --
 * business logic lives in services/, ai/, repositories/, etc. See README.md
 * for the full architecture overview.
 */
require('./functions/createCase');
require('./functions/answerQuestion');
require('./functions/finalizeCase');
require('./functions/getCase');
require('./functions/listCases');
require('./functions/checkFreeCaseEligibility');
require('./functions/redeemFreeCase');
require('./functions/updatePolishedNarrative');
require('./functions/getCaseAICost');
require('./functions/findReferences');
require('./functions/answerFacultyQuestion');
require('./functions/correctDictation');
require('./functions/deleteAccount');
