import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const occ = require('./occasions.js');

test('classifies the same home-cooked groups as the app', () => {
  assert.equal(occ.mealOccasionId({ title: 'Dal rice', time_slot: '1:00 PM' }), occ.EVERYDAY);
  assert.equal(occ.mealOccasionId({ title: 'Plain biryani' }), occ.EVERYDAY);
  assert.equal(occ.mealOccasionId({ title: 'Diwali laddu' }), occ.FESTIVE);
  assert.equal(occ.mealOccasionId({ title: 'Holi namkeen' }), occ.FESTIVE);
  assert.equal(occ.mealOccasionId({ title: 'Eid biryani' }), occ.FESTIVE);
  assert.equal(occ.mealOccasionId({ title: 'Birthday cake' }), occ.PARTY);
  assert.equal(occ.mealOccasionId({ title: 'Namkeen' }), occ.SPECIALTY);
  assert.equal(occ.mealOccasionId({ title: 'Ganesh modak' }), occ.SPECIALTY);
  assert.equal(occ.mealOccasionId({ title: 'Holiday thali' }), occ.EVERYDAY);
  assert.equal(occ.mealOccasionId({ title: 'Diwali laddu', occasion: 'specialty' }), occ.SPECIALTY);
});

test('slices stay inside the group', () => {
  assert.equal(occ.matchesOccasion({ title: 'Diwali laddu' }, occ.FESTIVE, 'diwali'), true);
  assert.equal(occ.matchesOccasion({ title: 'Diwali laddu' }, occ.SPECIALTY, 'sweet'), false);
  assert.equal(occ.matchesOccasion({ title: 'Ganesh modak' }, occ.SPECIALTY, 'seasonal'), true);
  assert.equal(occ.matchesOccasion({ title: 'Winter bhaji' }, occ.EVERYDAY, 'seasonal'), true);
});

test('a broadcast can be built for every tab and slice', () => {
  for (const tab of occ.TABS) {
    for (const slice of tab.slices) {
      const body = occ.broadcastInsert({
        customerId: 'diner-1',
        customerEmail: 'diner@example.com',
        customerPhone: '9999999999',
        occasion: tab.id,
        slice: slice[0],
        note: 'Cook this',
        quantity: 1,
        address: '12 Lane, Pune',
        targetIso: '2026-11-02T13:00:00.000Z',
      });
      assert.equal(body.request_type, 'broadcast');
      assert.equal(body.occasion, tab.id);
      assert.equal(body.target_chef_ids.length, 0);
      assert.equal(body.quantity, 1);
      assert.ok(body.description.startsWith('Occasion:'));
      if (slice[0] === occ.SLICE_ALL) assert.equal(body.occasion_slice, null);
      else assert.equal(body.occasion_slice, slice[0]);
    }
  }
});
