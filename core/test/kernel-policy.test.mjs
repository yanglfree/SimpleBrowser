import test from 'node:test';
import assert from 'node:assert/strict';
import { DESKTOP_USER_AGENT } from '../src/constants.mjs';
import {
  canNavigateBack,
  clampProgress,
  desktopUrlFor,
  isBackwardStep,
  shouldRefreshNavigationState,
  shouldReturnHomeOnBack,
  userAgentFor
} from '../src/kernel-policy.mjs';

test('progress and history helpers stay aligned with WebKernelService', () => {
  assert.equal(clampProgress(Number.NaN), 0);
  assert.equal(clampProgress(-4), 0);
  assert.equal(clampProgress(140), 100);
  assert.equal(clampProgress(42), 42);
  assert.equal(isBackwardStep(-1), true);
  assert.equal(isBackwardStep(0), false);
  assert.equal(shouldRefreshNavigationState(true), true);
  assert.equal(shouldRefreshNavigationState(false), false);
});

test('back from a loaded page without kernel history returns to native home', () => {
  assert.equal(shouldReturnHomeOnBack(false, false), true);
  assert.equal(canNavigateBack(false, false), true);
  assert.equal(canNavigateBack(false, true), false);
  assert.equal(canNavigateBack(true, false), true);
});

test('desktop UA rewrite only special-cases m.weibo.cn', () => {
  const mobile = 'Mozilla/5.0 (iPhone)';
  assert.equal(userAgentFor(true, mobile), DESKTOP_USER_AGENT);
  assert.equal(userAgentFor(false, mobile), mobile);
  assert.equal(
    desktopUrlFor('https://m.weibo.cn/status/1?foo=1'),
    'https://weibo.com/status/1?foo=1'
  );
  assert.equal(desktopUrlFor('https://www.zhihu.com/'), 'https://www.zhihu.com/');
});
