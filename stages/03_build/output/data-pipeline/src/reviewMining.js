// Keyword-based noise-mention mining, per ranking-spec.md.
// Deliberately simple (word/phrase matching, not a trained model) so it's
// cheap to run over review text pulled from the Places/Yelp APIs and easy
// for a human to audit which phrases drove a score.

const POSITIVE_PHRASES = [
  'quiet',
  'peaceful',
  'great for conversation',
  'easy to talk',
  'could hear each other',
  'calm atmosphere',
  'not loud',
  'low key',
];

const NEGATIVE_PHRASES = [
  'loud',
  'noisy',
  "couldn't hear",
  'could not hear',
  'hard to hear',
  'had to shout',
  'ear-splitting',
  'deafening',
  'too much noise',
];

function countPhraseOccurrences(text, phrases) {
  const lower = text.toLowerCase();
  return phrases.reduce((count, phrase) => {
    let idx = 0;
    let found = 0;
    while ((idx = lower.indexOf(phrase, idx)) !== -1) {
      found += 1;
      idx += phrase.length;
    }
    return count + found;
  }, 0);
}

/**
 * Mines an array of review text strings for noise-related mentions.
 * @param {string[]} reviewTexts
 * @returns {{positiveCount: number, negativeCount: number}}
 */
export function mineNoiseMentions(reviewTexts) {
  let positiveCount = 0;
  let negativeCount = 0;

  for (const text of reviewTexts || []) {
    if (!text) continue;
    positiveCount += countPhraseOccurrences(text, POSITIVE_PHRASES);
    negativeCount += countPhraseOccurrences(text, NEGATIVE_PHRASES);
  }

  return { positiveCount, negativeCount };
}

export { POSITIVE_PHRASES, NEGATIVE_PHRASES };
