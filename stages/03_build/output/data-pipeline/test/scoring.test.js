import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  reviewSubscore,
  popularSubscore,
  dbaToSubscore,
  micSubscore,
  voteSubscore,
  filterVotesSupersededByMic,
  combineScores,
  MIN_REVIEW_MENTIONS,
} from '../src/scoring.js';

test('reviewSubscore returns null below the minimum mention count', () => {
  assert.equal(reviewSubscore(0, 0), null);
  assert.equal(MIN_REVIEW_MENTIONS, 1);
});

test('reviewSubscore scores a single mention (lowered threshold)', () => {
  assert.equal(reviewSubscore(1, 0), 100);
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

test('micSubscore weights web readings lower than android', () => {
  // iOS avg 60 dBA (weight 1.0), web avg 80 dBA (weight 0.35).
  const score = micSubscore([
    { decibel: 60, platform: 'ios' },
    { decibel: 80, platform: 'web' },
  ]);
  const expectedDba = (60 * 1.0 + 80 * 0.35) / 1.35;
  assert.equal(score, dbaToSubscore(expectedDba));
});

test('voteSubscore returns null with no votes', () => {
  assert.equal(voteSubscore([]), null);
  assert.equal(voteSubscore(undefined), null);
});

test('voteSubscore averages quiet/normal/loud onto 0-100', () => {
  assert.equal(voteSubscore([{ vote: 'quiet' }]), 100);
  assert.equal(voteSubscore([{ vote: 'normal' }]), 50);
  assert.equal(voteSubscore([{ vote: 'loud' }]), 0);
  assert.equal(voteSubscore([{ vote: 'quiet' }, { vote: 'loud' }]), 50);
});

test('filterVotesSupersededByMic drops a vote with a same-user mic reading within 5 minutes', () => {
  const voteTime = new Date('2026-08-18T12:00:00Z');
  const votes = [{ userId: 'u1', vote: 'loud', submittedAt: voteTime }];
  const micReadings = [{ userId: 'u1', submittedAt: new Date('2026-08-18T12:03:00Z') }];
  assert.deepEqual(filterVotesSupersededByMic(votes, micReadings), []);
});

test('filterVotesSupersededByMic keeps a vote when the mic reading is a different user', () => {
  const voteTime = new Date('2026-08-18T12:00:00Z');
  const votes = [{ userId: 'u1', vote: 'loud', submittedAt: voteTime }];
  const micReadings = [{ userId: 'u2', submittedAt: new Date('2026-08-18T12:01:00Z') }];
  assert.deepEqual(filterVotesSupersededByMic(votes, micReadings), votes);
});

test('filterVotesSupersededByMic keeps a vote when the same-user mic reading is more than 5 minutes away', () => {
  const voteTime = new Date('2026-08-18T12:00:00Z');
  const votes = [{ userId: 'u1', vote: 'loud', submittedAt: voteTime }];
  const micReadings = [{ userId: 'u1', submittedAt: new Date('2026-08-18T12:06:00Z') }];
  assert.deepEqual(filterVotesSupersededByMic(votes, micReadings), votes);
});

test('combineScores includes the vote signal in both score and confidence', () => {
  const result = combineScores({
    review: {},
    popular: {},
    mic: {},
    vote: { subscore: 100, count: 3 },
  });
  assert.equal(result.score, 100);
  assert.equal(result.confidence, 'Low'); // vote tier: count 3 -> 2 points
  assert.equal(result.signalCount, 1);
});

test('combineScores returns null when no signals are present', () => {
  const result = combineScores({ review: { subscore: null }, popular: {}, mic: { subscore: null } });
  assert.equal(result.score, null);
  assert.equal(result.confidence, null);
  assert.equal(result.signalCount, 0);
});

test('combineScores marks "Very Low" confidence for a single thin signal (1 review mention)', () => {
  // Matches Caelan's rule: any noise mention at all is at least Very Low confidence.
  const result = combineScores({ review: { subscore: 80, count: 1 }, popular: {}, mic: { subscore: null } });
  assert.equal(result.score, 80);
  assert.equal(result.confidence, 'Very Low');
  assert.equal(result.signalCount, 1);
});

test('combineScores scales confidence up with review mention volume alone', () => {
  assert.equal(combineScores({ review: { subscore: 80, count: 2 }, popular: {}, mic: {} }).confidence, 'Very Low');
  assert.equal(combineScores({ review: { subscore: 80, count: 3 }, popular: {}, mic: {} }).confidence, 'Low');
  assert.equal(combineScores({ review: { subscore: 80, count: 5 }, popular: {}, mic: {} }).confidence, 'Low');
  assert.equal(combineScores({ review: { subscore: 80, count: 6 }, popular: {}, mic: {} }).confidence, 'Moderate');
});

test('combineScores scales confidence up with mic reading volume alone', () => {
  assert.equal(combineScores({ review: {}, popular: {}, mic: { subscore: 60, count: 1 } }).confidence, 'Very Low');
  assert.equal(combineScores({ review: {}, popular: {}, mic: { subscore: 60, count: 3 } }).confidence, 'Low');
  assert.equal(combineScores({ review: {}, popular: {}, mic: { subscore: 60, count: 10 } }).confidence, 'Moderate');
});

test('combineScores reaches "Certain" when both review and mic are at their strongest tier', () => {
  const result = combineScores({
    review: { subscore: 100, count: 100 },
    popular: {},
    mic: { subscore: 100, count: 100 },
  });
  assert.equal(result.score, 100);
  assert.equal(result.confidence, 'Certain');
  assert.equal(result.signalCount, 2);
});

test('combineScores renormalizes weights over present signals only', () => {
  // Only review (weight 0.25) and popular (weight 0.15) present.
  // Renormalized: review gets 0.25/0.4 = 0.625, popular gets 0.15/0.4 = 0.375.
  const result = combineScores({
    review: { subscore: 100, count: 4 },
    popular: { subscore: 0 },
    mic: { subscore: null },
  });
  assert.equal(result.score, 62.5); // 100*0.625 + 0*0.375
  // review tier (count 4 -> 2pts) + popular present (3pts, dormant weight but still counted) = 5.
  assert.equal(result.confidence, 'Very High');
});
