import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parsePopularTimes } from '../src/outscraper.js';

test('parsePopularTimes returns null when popular_times is absent', () => {
  // This is the realistic case per Outscraper's own community reports of
  // popular_times intermittently missing — see the warning in src/outscraper.js.
  assert.equal(parsePopularTimes({ name: 'A Restaurant' }), null);
  assert.equal(parsePopularTimes({}), null);
  assert.equal(parsePopularTimes(undefined), null);
});

test('parsePopularTimes extracts the current hour percentage when present', () => {
  const now = new Date();
  const place = {
    popular_times: [
      {
        day_int: now.getDay(),
        popular_times: [{ hour: now.getHours(), percentage: 42 }],
      },
    ],
  };
  assert.equal(parsePopularTimes(place), 42);
});

test('parsePopularTimes falls back to the day\'s peak when the current hour is missing', () => {
  const now = new Date();
  const otherHour = (now.getHours() + 5) % 24;
  const place = {
    popular_times: [
      {
        day_int: now.getDay(),
        popular_times: [{ hour: otherHour, percentage: 77 }],
      },
    ],
  };
  assert.equal(parsePopularTimes(place), 77);
});
