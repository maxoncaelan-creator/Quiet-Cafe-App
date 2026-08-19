import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normalizePriceLevel, extractSuburb, extractSuburbFromAddress, createRequestBudget } from '../src/places.js';

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

test('createRequestBudget allows exactly `limit` requests then refuses', () => {
  const budget = createRequestBudget(2);
  assert.equal(budget.take(), true);
  assert.equal(budget.remaining, 1);
  assert.equal(budget.take(), true);
  assert.equal(budget.remaining, 0);
  assert.equal(budget.take(), false);
  assert.equal(budget.remaining, 0);
});

test('createRequestBudget of 0 refuses immediately', () => {
  const budget = createRequestBudget(0);
  assert.equal(budget.take(), false);
});

test('extractSuburbFromAddress parses the normal "<street>, <suburb> <STATE> <postcode>, Australia" shape', () => {
  assert.equal(
    extractSuburbFromAddress('17 Willoughby St, Kirribilli NSW 2061, Australia'),
    'Kirribilli'
  );
  assert.equal(
    extractSuburbFromAddress('Ground Floor/5-7 Young St, Sydney NSW 2000, Australia'),
    'Sydney'
  );
  assert.equal(
    extractSuburbFromAddress('2/320 Church St, Parramatta NSW 2150, Australia'),
    'Parramatta'
  );
});

test('extractSuburbFromAddress parses the reversed "Australia, <state>, <suburb>, ..." shape', () => {
  assert.equal(
    extractSuburbFromAddress('Australia, New South Wales, Hornsby, Pacific Hwy, FC8'),
    'Hornsby'
  );
  assert.equal(
    extractSuburbFromAddress('Australia, New South Wales, Castle Hill, Castle St, Level 2邮政编码: 2154'),
    'Castle Hill'
  );
});

test('extractSuburbFromAddress returns null for non-Australian addresses', () => {
  // Real contamination seen in the dataset: a "Picton NSW" area query also
  // matched Picton, New Zealand and Picton, Ontario, Canada.
  assert.equal(extractSuburbFromAddress('1 High Street, Picton 7220, New Zealand'), null);
  assert.equal(extractSuburbFromAddress('19 Elizabeth St, Picton, ON K0K 2T0, Canada'), null);
});

test('extractSuburbFromAddress returns null for missing input', () => {
  assert.equal(extractSuburbFromAddress(null), null);
  assert.equal(extractSuburbFromAddress(undefined), null);
  assert.equal(extractSuburbFromAddress(''), null);
});
