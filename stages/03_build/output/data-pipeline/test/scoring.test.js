import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  reviewSubscore,
  popularSubscore,
  dbaToSubscore,
  micSubscore,
  combineScores,
  MIN_REVIEW_MENTIONS,
} from '../src/scoring.js';

test('reviewSubscore returns null below the minimum mention count', () => {
  assert.equal(reviewSubscore(1, 1), null);
  assert.equal(MIN_REVIEW_MENTIONS, 3);
});

test('reviewSubscore scores all-positive mentions at 100', () => {
  assert.equal(reviewSubscore(4, 0), 100);
});

test('reviewSubscore scores all-negative mentions at 0', () => {
  assert.equal(reviewSubscore(0, 4), 0);
});

test('reviewSubscore is a ratio when mixed', () => {
  assert.equal(reviewSubscore(3, 1), 75);
});

test('popularSubscore inverts busyness', () => {
  assert.equal(popularSubscore(0), 100);
  assert.equal(popularSubscore(100), 0);
  assert.equal(popularSubscore(30), 70);
});

test('popularSubscore returns null when there is no data', () => {
  assert.equal(popularSubscore(null), null);
  assert.equal(popularSubscore(undefined), null);
});

test('dbaToSubscore maps the configured range to 0-100', () => {
  assert.equal(dbaToSubscore(50), 100); // MIN_DBA -> quietest
  assert.equal(dbaToSubscore(90), 0); // MAX_DBA -> loudest
  assert.equal(dbaToSubscore(70), 50); // midpoint
});

test('dbaToSubscore clamps outside the configured range', () => {
  assert.equal(dbaToSubscore(30), 100);
  assert.equal(dbaToSubscore(120), 0);
});

test('micSubscore returns null with no readings', () => {
  assert.equal(micSubscore([]), null);
  assert.equal(micSubscore(undefined), null);
});

test('micSubscore averages within a platform before combining', () => {
  // Two iOS readings at 60 and 70 dBA -> platform average 65 dBA.
  const score = micSubscore([
    { decibel: 60, platform: 'ios' },
    { decibel: 70, platform: 'ios' },
  ]);
  assert.equal(score, dbaToSubscore(65));
});

test('micSubscore weights android readings at half of ios', () => {
  // iOS avg 60 dBA (weight 1.0), Android avg 80 dBA (weight 0.5).
  // Weighted dBA = (60*1.0 + 80*0.5) / 1.5 = 66.67
  const score = micSubscore([
    { decibel: 60, platform: 'ios' },
    { decibel: 80, platform: 'android' },
  ]);
  const expectedDba = (60 * 1.0 + 80 * 0.5) / 1.5;
  assert.equal(score, dbaToSubscore(expectedDba));
});

test('combineScores returns null when no signals are present', () => {
  const result = combineScores({ review: null, popular: null, mic: null });
  assert.equal(result.score, null);
  assert.equal(result.confidence, null);
  assert.equal(result.signalCount, 0);
});

test('combineScores marks low confidence with one signal', () => {
  const result = combineScores({ review: 80, popular: null, mic: null });
  assert.equal(result.score, 80);
  assert.equal(result.confidence, 'low');
  assert.equal(result.signalCount, 1);
});

test('combineScores marks high confidence and renormalizes weights with all three signals', () => {
  const result = combineScores({ review: 100, popular: 100, mic: 100 });
  assert.equal(result.score, 100);
  assert.equal(result.confidence, 'high');
  assert.equal(result.signalCount, 3);
});

test('combineScores renormalizes weights over present signals only', () => {
  // Only review (weight 0.3) and popular (weight 0.2) present.
  // Renormalized: review gets 0.3/0.5 = 0.6, popular gets 0.2/0.5 = 0.4.
  const result = combineScores({ review: 100, popular: 0, mic: null });
  assert.equal(result.score, 60); // 100*0.6 + 0*0.4
  assert.equal(result.confidence, 'medium');
});
