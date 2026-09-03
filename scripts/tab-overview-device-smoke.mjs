import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Open the overview first. This test closes only the explicitly supplied tab.
// Use a disposable tab; never point this at a tab containing unsaved work.
const [tabId, outputDirectory] = process.argv.slice(2);
assert(tabId && outputDirectory,
  'Usage: node scripts/tab-overview-device-smoke.mjs <disposable-tab-id> <output-directory>');
const directory = resolve(outputDirectory);
mkdirSync(directory, { recursive: true });

function hdc(...args) {
  return execFileSync('hdc', args, { encoding: 'utf8' });
}

function attributes(node) {
  return [node.attributes, ...(node.children ?? []).flatMap(attributes)].filter(Boolean);
}

function snapshot(name) {
  const output = hdc('shell', 'uitest', 'dumpLayout');
  const remotePath = output.match(/DumpLayout saved to:(\S+)/)?.[1];
  assert(remotePath, output);
  const localPath = resolve(directory, `${name}.json`);
  hdc('file', 'recv', remotePath, localPath);
  return attributes(JSON.parse(readFileSync(localPath, 'utf8')));
}

function closeIds(nodes) {
  return nodes.map(node => node.id ?? '').filter(id => id.startsWith('close-tab-')).sort();
}

const before = snapshot('before-close');
const targetId = `close-tab-${tabId}`;
const target = before.find(node => node.id === targetId);
assert(target, `Open the overview with ${targetId} visible before running this test`);
assert.equal(target.visible, 'true', 'Scroll the target card into view first');
assert.equal(target.enabled, 'true');
const initialIds = closeIds(before);
assert(initialIds.length > 2, 'Keep at least two other tabs to avoid last-tab dismissal semantics');
const bounds = target.bounds.match(/-?\d+/g).map(Number);
assert.equal(bounds.length, 4);
hdc('shell', 'uitest', 'uiInput', 'click',
  String(Math.round((bounds[0] + bounds[2]) / 2)),
  String(Math.round((bounds[1] + bounds[3]) / 2)));

const after = snapshot('after-close');
const actualIds = closeIds(after);
assert.deepEqual(actualIds, initialIds.filter(id => id !== targetId),
  'Close must remove exactly the target card and keep the overview open');
assert(!after.some(node => node.id === `tab-view-${tabId}`),
  'The closed tab must also disappear from the underlying page tree');
const remoteImage = '/data/local/tmp/zhuo-tab-close-smoke.jpeg';
hdc('shell', 'snapshot_display', '-f', remoteImage);
hdc('file', 'recv', remoteImage, resolve(directory, 'after-close.jpeg'));
console.log(`PASS: ${initialIds.length} -> ${actualIds.length} cards; ${tabId} removed; overview remains open`);
