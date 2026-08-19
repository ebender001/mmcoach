jest.mock('https');
const https = require('https');
const pubmedService = require('../cloud/services/pubmedService');
const { ExternalServiceError } = require('../cloud/utils/errors');

function mockHttpsRoutes(routes) {
  https.request.mockImplementation((options, callback) => {
    const route = routes.find((r) => options.path.includes(r.match));
    const { statusCode, body } = (route && route.response) || { statusCode: 500, body: '' };
    const res = {
      statusCode,
      on: (event, handler) => {
        if (event === 'data') handler(Buffer.from(body));
        if (event === 'end') handler();
      },
    };
    callback(res);
    return { on: () => {}, write: () => {}, end: () => {}, destroy: () => {} };
  });
}

const MEDLINE_SAMPLE = `PMID- 111
TI  - Postoperative bleeding after cardiac surgery: a review
AB  - This review discusses postoperative bleeding after cardiac
      surgery and management strategies.
AU  - Smith J
AU  - Doe A
TA  - J Thorac Surg
DP  - 2019 Jun

PMID- 222
TI  - Timing of surgical re-exploration for bleeding
AB  - We evaluate optimal timing for re-exploration.
AU  - Lee K
TA  - Ann Surg
DP  - 2020

`;

afterEach(() => jest.clearAllMocks());

describe('pubmedService.parseMedline', () => {
  it('parses multiple MEDLINE records, joining continuation lines', () => {
    const records = pubmedService.parseMedline(MEDLINE_SAMPLE);

    expect(records).toHaveLength(2);
    expect(records[0]).toMatchObject({
      pmid: '111',
      title: 'Postoperative bleeding after cardiac surgery: a review',
      abstract: 'This review discusses postoperative bleeding after cardiac surgery and management strategies.',
      authors: ['Smith J', 'Doe A'],
      journal: 'J Thorac Surg',
      year: '2019',
    });
    expect(records[1]).toMatchObject({ pmid: '222', title: 'Timing of surgical re-exploration for bleeding' });
  });
});

describe('pubmedService.splitAbstractSections', () => {
  it('returns a single unlabeled section for an unstructured abstract', () => {
    const sections = pubmedService.splitAbstractSections('This review discusses postoperative bleeding.');

    expect(sections).toEqual([{ label: null, text: 'This review discusses postoperative bleeding.' }]);
  });

  it('splits a structured abstract into labeled sections', () => {
    const abstract =
      'BACKGROUND: Bleeding after cardiac surgery is common. ' +
      'METHODS: We reviewed 200 cases retrospectively. ' +
      'RESULTS: Re-exploration within 4 hours reduced transfusion needs. ' +
      'CONCLUSIONS: Early re-exploration should be considered.';

    const sections = pubmedService.splitAbstractSections(abstract);

    expect(sections).toEqual([
      { label: 'Background', text: 'Bleeding after cardiac surgery is common.' },
      { label: 'Methods', text: 'We reviewed 200 cases retrospectively.' },
      { label: 'Results', text: 'Re-exploration within 4 hours reduced transfusion needs.' },
      { label: 'Conclusions', text: 'Early re-exploration should be considered.' },
    ]);
  });

  it('title-cases multi-word labels', () => {
    const sections = pubmedService.splitAbstractSections('MAIN OUTCOME MEASURES: 30-day mortality.');

    expect(sections[0].label).toBe('Main Outcome Measures');
  });

  it('does not treat short all-caps abbreviations as section labels', () => {
    const sections = pubmedService.splitAbstractSections('The odds ratio was OR: 2.1 with CI: 1.4-3.0.');

    expect(sections).toEqual([{ label: null, text: 'The odds ratio was OR: 2.1 with CI: 1.4-3.0.' }]);
  });

  it('returns [] for a null/empty abstract', () => {
    expect(pubmedService.splitAbstractSections(null)).toEqual([]);
    expect(pubmedService.splitAbstractSections('')).toEqual([]);
  });
});

describe('pubmedService.findReferences', () => {
  it('returns [] without fetching abstracts when esearch finds nothing', async () => {
    mockHttpsRoutes([
      { match: 'esearch.fcgi', response: { statusCode: 200, body: JSON.stringify({ esearchresult: { idlist: [] } }) } },
    ]);

    const results = await pubmedService.findReferences({ query: 'a very obscure topic', maxResults: 5 });

    expect(results).toEqual([]);
    expect(https.request).toHaveBeenCalledTimes(1);
  });

  it('returns results in esearch relevance order with abstracts attached', async () => {
    mockHttpsRoutes([
      {
        match: 'esearch.fcgi',
        response: { statusCode: 200, body: JSON.stringify({ esearchresult: { idlist: ['111', '222'] } }) },
      },
      { match: 'efetch.fcgi', response: { statusCode: 200, body: MEDLINE_SAMPLE } },
    ]);

    const results = await pubmedService.findReferences({ query: 'postoperative bleeding', maxResults: 5 });

    expect(results).toHaveLength(2);
    expect(results[0]).toEqual({
      pmid: '111',
      title: 'Postoperative bleeding after cardiac surgery: a review',
      authors: ['Smith J', 'Doe A'],
      journal: 'J Thorac Surg',
      year: '2019',
      abstractSections: [
        { label: null, text: 'This review discusses postoperative bleeding after cardiac surgery and management strategies.' },
      ],
      url: 'https://pubmed.ncbi.nlm.nih.gov/111/',
    });
    expect(results[1].pmid).toBe('222');
  });

  it('throws ExternalServiceError when esearch keeps failing', async () => {
    mockHttpsRoutes([{ match: 'esearch.fcgi', response: { statusCode: 500, body: '' } }]);

    await expect(
      pubmedService.findReferences({ query: 'postoperative bleeding', maxResults: 5 })
    ).rejects.toThrow(ExternalServiceError);
  });

  it('throws ExternalServiceError when esearch returns unparseable JSON', async () => {
    mockHttpsRoutes([{ match: 'esearch.fcgi', response: { statusCode: 200, body: 'not json' } }]);

    await expect(
      pubmedService.findReferences({ query: 'postoperative bleeding', maxResults: 5 })
    ).rejects.toThrow(ExternalServiceError);
  });
});
