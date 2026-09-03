import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

// Run after hvigorw assembleHap with the generated SettingsPage.ts path.
// Exercise the compiler's refresh callbacks: passing a computed label by value
// previously left the text outside state observation despite passing service tests.
const compiledPath = process.argv[2];
assert(compiledPath, 'Usage: node scripts/verify-rules-update-render.mjs <compiled-SettingsPage.ts>');
const source = readFileSync(compiledPath, 'utf8');
const start = source.indexOf('    private RulesUpdateRow(');
const end = source.indexOf('    private ValueRowText(', start);
assert(start >= 0 && end > start, 'Build the current SettingsPage before verification');

let activeCallback;
let busy = false;
let enabled = true;
let title;
let spinnerCount = 0;
let lastUpdatedCount = 0;
const dependencies = new Set();
function component(handlers = {}) {
  return new Proxy(handlers, { get: (target, key) => target[key] ?? (() => {}) });
}
const Page = runInNewContext(stripTypeScriptTypes(`class Page {${source.slice(start, end)}}\nPage;`), {
  Row: component({ enabled: (value) => { enabled = value; } }),
  Text: component({ create: (value) => {
    if (value !== 'last-updated') title = value;
  } }),
  If: component(),
  LoadingProgress: component({ create: () => { spinnerCount++; } })
});
const page = new Page();
Object.defineProperty(page, 'isRulesUpdating', {
  get() {
    if (activeCallback) dependencies.add(activeCallback);
    return busy;
  }
});
page.onUpdateRules = () => {};
page.rulesLastUpdatedLabel = () => { lastUpdatedCount++; return 'last-updated'; };
function render(callback) {
  const previous = activeCallback;
  activeCallback = callback;
  callback(0, previous === undefined);
  activeCallback = previous;
}
page.observeComponentCreation2 = render;
page.ifElseBranchUpdateFunction = (_branch, callback) => callback();
page.RulesUpdateRow();
assert.equal(enabled, true);
assert.equal(spinnerCount, 0);
assert.equal(lastUpdatedCount, 1);
const idleTitle = title;
assert.ok(idleTitle);

busy = true;
for (const callback of [...dependencies]) render(callback);
assert.equal(enabled, false, 'An in-progress update must disable its row');
assert.notDeepEqual(title, idleTitle, 'The title must change in the observed refresh callback');
assert.equal(spinnerCount, 1, 'A refresh must create the loading indicator');
assert.equal(lastUpdatedCount, 1, 'The timestamp must not replace the in-progress indicator');

busy = false;
for (const callback of [...dependencies]) render(callback);
assert.equal(enabled, true);
assert.deepEqual(title, idleTitle);
assert.equal(lastUpdatedCount, 2, 'Completion must restore the latest update time');
console.log('PASS: compiled row observes idle -> updating -> idle without rebuilding the settings page');
