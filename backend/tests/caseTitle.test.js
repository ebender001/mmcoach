const { deriveTitle } = require('../cloud/utils/caseTitle');

describe('deriveTitle', () => {
  it('returns the narrative unchanged when 60 characters or shorter', () => {
    expect(deriveTitle('A 68-year-old man underwent CABG x3.')).toBe('A 68-year-old man underwent CABG x3.');
  });

  it('truncates to 60 characters with an ellipsis when longer', () => {
    const narrative = 'A 68-year-old man underwent CABG x3 and later became hypotensive with increasing chest tube output.';
    const title = deriveTitle(narrative);

    expect(title.endsWith('…')).toBe(true);
    expect(title.length).toBe(61);
    expect(narrative.startsWith(title.slice(0, -1))).toBe(true);
  });

  it('collapses newlines into a single line', () => {
    expect(deriveTitle('Line one\nLine two')).toBe('Line one Line two');
  });

  it('returns an empty string for empty or missing input', () => {
    expect(deriveTitle('')).toBe('');
    expect(deriveTitle(undefined)).toBe('');
  });
});
