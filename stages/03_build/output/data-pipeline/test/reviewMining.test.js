import { test } from 'node:test';
import assert from 'node:assert/strict';

import { mineNoiseMentions } from '../src/reviewMining.js';

test('mineNoiseMentions counts positive and negative phrases', () => {
  const result = mineNoiseMentions([
    'So quiet, we could actually talk the whole meal.',
    'A bit loud on weekends but otherwise fine.',
  ]);
  assert.equal(result.positiveCount, 1);
  assert.equal(result.negativeCount, 1);
});

test('mineNoiseMentions is case-insensitive', () => {
  const result = mineNoiseMentions(['LOUD music, could not hear a thing.']);
  assert.equal(result.negativeCount, 2); // "loud" + "could not hear"
});

test('mineNoiseMentions handles empty or missing text', () => {
  assert.deepEqual(mineNoiseMentions([]), { positiveCount: 0, negativeCount: 0 });
  assert.deepEqual(mineNoiseMentions(undefined), { positiveCount: 0, negativeCount: 0 });
  assert.deepEqual(mineNoiseMentions([null, '', undefined]), {
    positiveCount: 0,
    negativeCount: 0,
  });
});
