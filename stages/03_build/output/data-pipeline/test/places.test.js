import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normalizePriceLevel } from '../src/places.js';

test('normalizePriceLevel maps Places API (New) enums to 1-4', () => {
  assert.equal(normalizePriceLevel('PRICE_LEVEL_FREE'), 1);
  assert.equal(normalizePriceLevel('PRICE_LEVEL_INEXPENSIVE'), 1);
  assert.equal(normalizePriceLevel('PRICE_LEVEL_MODERATE'), 2);
  assert.equal(normalizePriceLevel('PRICE_LEVEL_EXPENSIVE'), 3);
  assert.equal(normalizePriceLevel('PRICE_LEVEL_VERY_EXPENSIVE'), 4);
});

test('normalizePriceLevel returns null for unspecified or missing values', () => {
  assert.equal(normalizePriceLevel('PRICE_LEVEL_UNSPECIFIED'), null);
  assert.equal(normalizePriceLevel(undefined), null);
  assert.equal(normalizePriceLevel(null), null);
});
