/**
 * The only module that talks to NCBI's PubMed E-utilities. Mirrors
 * aiService.js's role for OpenAI: Node's built-in https only, no runtime
 * npm dependency (including no XML parser -- efetch is requested in
 * MEDLINE plain-text format specifically so this can be parsed with a
 * small line-based state machine instead).
 */
const https = require('https');
const logger = require('../utils/logger');
const { ExternalServiceError } = require('../utils/errors');

const HOST = 'eutils.ncbi.nlm.nih.gov';
const BASE_PATH = '/entrez/eutils';
const DEFAULT_TIMEOUT_MS = 15000;
const DEFAULT_MAX_RETRIES = 1;

/**
 * NCBI asks (but does not require) an API key for higher rate limits and
 * a contact tool/email as courtesy identification. Both are optional --
 * omitted entirely if not configured, never fabricated.
 */
function identificationParams() {
  const key = process.env.PUBMED_API_KEY;
  const email = process.env.PUBMED_CONTACT_EMAIL;
  let params = '';
  if (key) params += `&api_key=${encodeURIComponent(key)}`;
  if (email) params += `&tool=MMCoach&email=${encodeURIComponent(email)}`;
  return params;
}

function getText(path, { timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      { hostname: HOST, path, method: 'GET', timeout: timeoutMs },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => {
          raw += chunk;
        });
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, raw });
        });
      }
    );
    req.on('timeout', () => {
      req.destroy(new Error('PubMed request timed out.'));
    });
    req.on('error', (err) => reject(err));
    req.end();
  });
}

async function requestWithRetry(path, attemptsLeft, context) {
  const startedAt = Date.now();
  try {
    const { statusCode, raw } = await getText(path);
    const latencyMs = Date.now() - startedAt;

    if (statusCode < 200 || statusCode >= 300) {
      const retriable = statusCode === 429 || statusCode >= 500;
      if (retriable && attemptsLeft > 0) {
        logger.warn({ ...context, event: 'pubmed_retry', statusCode, latencyMs });
        return requestWithRetry(path, attemptsLeft - 1, context);
      }
      logger.error({ ...context, event: 'pubmed_error', statusCode, latencyMs });
      throw new ExternalServiceError(`PubMed returned status ${statusCode}.`);
    }

    logger.info({ ...context, event: 'pubmed_success', latencyMs });
    return raw;
  } catch (err) {
    if (err instanceof ExternalServiceError) {
      throw err;
    }
    if (attemptsLeft > 0) {
      logger.warn({ ...context, event: 'pubmed_retry_after_error', message: err.message });
      return requestWithRetry(path, attemptsLeft - 1, context);
    }
    logger.error({ ...context, event: 'pubmed_failure', message: err.message });
    throw new ExternalServiceError(`Failed to reach PubMed: ${err.message}`);
  }
}

async function searchIds(query, maxResults) {
  const term = encodeURIComponent(query);
  const path =
    `${BASE_PATH}/esearch.fcgi?db=pubmed&retmode=json&sort=relevance&retmax=${maxResults}` +
    `&term=${term}${identificationParams()}`;
  const raw = await requestWithRetry(path, DEFAULT_MAX_RETRIES, { operation: 'esearch' });

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new ExternalServiceError('PubMed search returned an unparseable response.');
  }
  return (parsed.esearchresult && parsed.esearchresult.idlist) || [];
}

async function fetchMedline(ids) {
  if (ids.length === 0) return '';
  const idParam = encodeURIComponent(ids.join(','));
  const path =
    `${BASE_PATH}/efetch.fcgi?db=pubmed&id=${idParam}&rettype=medline&retmode=text${identificationParams()}`;
  return requestWithRetry(path, DEFAULT_MAX_RETRIES, { operation: 'efetch' });
}

/**
 * Parses NCBI's MEDLINE plain-text format into one record per PMID.
 * Fields are lines shaped `TAG  - value`; a field's value can continue
 * on following indented, untagged lines; a blank line separates records.
 * Only the fields MMCoach actually displays are extracted -- unrecognized
 * tags are ignored rather than causing a parse failure.
 */
function parseMedline(text) {
  const records = [];
  let current = null;
  let currentTag = null;

  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    const tagMatch = line.match(/^([A-Z]{2,4})\s*- ?(.*)$/);
    if (tagMatch) {
      const [, tag, value] = tagMatch;
      currentTag = tag;
      if (tag === 'PMID') {
        current = { pmid: value.trim(), title: '', abstract: '', authors: [], journal: '', year: '' };
        records.push(current);
        continue;
      }
      if (!current) continue;
      switch (tag) {
        case 'TI':
          current.title = value;
          break;
        case 'AB':
          current.abstract = value;
          break;
        case 'AU':
          current.authors.push(value.trim());
          break;
        case 'TA':
          current.journal = value;
          break;
        case 'DP':
          current.year = (value.match(/\d{4}/) || [''])[0];
          break;
        default:
          break;
      }
      continue;
    }

    if (line.trim() === '') {
      currentTag = null;
      continue;
    }

    if (current && currentTag && /^\s+\S/.test(line)) {
      const trimmed = line.trim();
      if (currentTag === 'TI') current.title += ` ${trimmed}`;
      else if (currentTag === 'AB') current.abstract += ` ${trimmed}`;
      else if (currentTag === 'TA') current.journal += ` ${trimmed}`;
    }
  }
  return records;
}

/**
 * NLM structured abstracts embed their section headers as run-in ALL-CAPS
 * labels (e.g. "BACKGROUND: ... METHODS: ... RESULTS: ... CONCLUSIONS: ..."),
 * which MEDLINE's plain-text format preserves in the `AB` field but as one
 * continuous run of text with no other markup. This splits that back into
 * `{ label, text }` sections so the client can render something other than
 * one dense paragraph. Requires the whitespace-anchored label to be at
 * least 3 letters (filters out things like "OR:"/"CI:") and colon-terminated;
 * an unstructured abstract (no such labels) comes back as a single
 * unlabeled section rather than being forced apart.
 */
const SECTION_LABEL_REGEX = /(?:^|(?<=\s))([A-Z][A-Z0-9 &/,-]{2,48}):\s/g;

function toTitleCase(label) {
  return label.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
}

function splitAbstractSections(text) {
  if (!text) return [];

  const labelMatches = [...text.matchAll(SECTION_LABEL_REGEX)];
  if (labelMatches.length === 0) {
    return [{ label: null, text: text.trim() }];
  }

  const sections = [];
  const firstStart = labelMatches[0].index;
  if (firstStart > 0) {
    const leading = text.slice(0, firstStart).trim();
    if (leading) sections.push({ label: null, text: leading });
  }

  labelMatches.forEach((match, i) => {
    const contentStart = match.index + match[0].length;
    const contentEnd = i + 1 < labelMatches.length ? labelMatches[i + 1].index : text.length;
    const content = text.slice(contentStart, contentEnd).trim();
    if (content) {
      sections.push({ label: toTitleCase(match[1].trim()), text: content });
    }
  });

  return sections;
}

function toClientResult(record) {
  return {
    pmid: record.pmid,
    title: record.title || 'Untitled',
    authors: record.authors,
    journal: record.journal || null,
    year: record.year || null,
    abstractSections: splitAbstractSections(record.abstract),
    url: `https://pubmed.ncbi.nlm.nih.gov/${record.pmid}/`,
  };
}

/**
 * Finds the `maxResults` PubMed articles most relevant to `query`, using
 * PubMed's own relevance sort (MMCoach does not re-rank). Returns `[]` if
 * nothing is found -- never fabricates a citation. Result order always
 * matches `esearch`'s relevance-ranked id list, even though `efetch`
 * doesn't strictly guarantee it echoes ids back in the requested order.
 */
async function findReferences({ query, maxResults = 5 }) {
  const ids = await searchIds(query, maxResults);
  if (ids.length === 0) return [];

  const medlineText = await fetchMedline(ids);
  const records = parseMedline(medlineText);
  const byPmid = new Map(records.map((record) => [record.pmid, record]));

  return ids
    .map((id) => byPmid.get(id))
    .filter(Boolean)
    .map(toClientResult);
}

module.exports = { findReferences, parseMedline, splitAbstractSections };
