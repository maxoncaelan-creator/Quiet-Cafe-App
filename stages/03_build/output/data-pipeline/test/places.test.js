import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normalizePriceLevel, extractSuburb } from '../src/places.js';

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

test('extractSuburb reads the locality component off a real-shaped address', () => {
  const addressComponents = [
    { longText: '12', types: ['street_number'] },
    { longText: 'Quiet St', types: ['route'] },
    { longText: 'Surry Hills', types: ['locality', 'political'] },
    { longText: 'New South Wales', types: ['administrative_area_level_1', 'political'] },
    { longText: 'Australia', types: ['country', 'political'] },
  ];
  assert.equal(extractSuburb(addressComponents), 'Surry Hills');
});

test('extractSuburb falls back to sublocality when there is no locality', () => {
  const addressComponents = [
    { longText: 'Dawes Point', types: ['sublocality_level_1', 'sublocality', 'political'] },
    { longText: 'New South Wales', types: ['administrative_area_level_1', 'political'] },
  ];
  assert.equal(extractSuburb(addressComponents), 'Dawes Point');
});

test('extractSuburb returns null when address components are missing or empty', () => {
  assert.equal(extractSuburb(undefined), null);
  assert.equal(extractSuburb([]), null);
});
