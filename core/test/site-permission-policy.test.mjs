import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SitePermissionDecision,
  applySitePermission,
  originFromParts,
  removeSitePermission,
  sitePermissionDecision
} from '../src/site-permission-policy.mjs';

test('unknown origin prompts; any deny wins; mixed prompt stays prompt', () => {
  assert.equal(sitePermissionDecision(undefined, ['camera']), SitePermissionDecision.Prompt);
  const stored = {
    origin: 'https://meet.example',
    camera: SitePermissionDecision.Allow,
    microphone: SitePermissionDecision.Deny,
    location: SitePermissionDecision.Prompt
  };
  assert.equal(sitePermissionDecision(stored, ['camera']), SitePermissionDecision.Allow);
  assert.equal(sitePermissionDecision(stored, ['camera', 'microphone']), SitePermissionDecision.Deny);
  assert.equal(sitePermissionDecision(stored, ['location']), SitePermissionDecision.Prompt);
});

test('applySitePermission updates only the requested kinds', () => {
  const next = applySitePermission([], 'https://maps.example', ['location'], SitePermissionDecision.Allow);
  assert.equal(next.length, 1);
  assert.equal(next[0].location, SitePermissionDecision.Allow);
  assert.equal(next[0].camera, SitePermissionDecision.Prompt);
  const denied = applySitePermission(next, 'https://maps.example', ['camera'], SitePermissionDecision.Deny);
  assert.equal(denied[0].location, SitePermissionDecision.Allow);
  assert.equal(denied[0].camera, SitePermissionDecision.Deny);
  assert.equal(removeSitePermission(denied, 'https://maps.example').length, 0);
});

test('origin omits default ports', () => {
  assert.equal(originFromParts('https', 'example.com', 443), 'https://example.com');
  assert.equal(originFromParts('http', '127.0.0.1', 4188), 'http://127.0.0.1:4188');
});
