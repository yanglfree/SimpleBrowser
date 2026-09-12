import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isTabLive,
  liveTabIds,
  persistableTabs,
  shouldFetchFavicon,
  shouldRecordHistory,
  shouldRecordSiteStats
} from '../src/session-policy.mjs';

test('private tabs never persist', () => {
  const tabs = [
    { id: 'a', isPrivate: false },
    { id: 'b', isPrivate: true },
    { id: 'c', isPrivate: false }
  ];
  assert.deepEqual(persistableTabs(tabs).map((tab) => tab.id), ['a', 'c']);
  assert.equal(shouldRecordHistory(true), false);
  assert.equal(shouldRecordHistory(false), true);
  assert.equal(shouldRecordSiteStats(true), false);
  assert.equal(shouldFetchFavicon(true), false);
});

test('live-webview budget always keeps the active tab', () => {
  const tabs = [{ id: 'one' }, { id: 'two' }, { id: 'three' }, { id: 'four' }, { id: 'five' }];
  const live = liveTabIds(tabs, 'five', 2);
  assert.deepEqual(live, ['five', 'one']);
  assert.equal(isTabLive(live, 'five'), true);
  assert.equal(isTabLive(live, 'two'), false);
});
