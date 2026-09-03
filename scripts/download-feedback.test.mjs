import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const states = { Pending: 0, Downloading: 1, Paused: 2, Completed: 3, Failed: 4, Canceled: 5 };
const presentation = readFileSync(new URL('../entry/src/main/ets/services/DownloadPresentation.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
const index = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const start = index.indexOf('  private downloadListener:');
const end = index.indexOf('  async aboutToAppear()', start);
assert.ok(start >= 0 && end > start);
const { Page, downloadErrorLabel } = runInNewContext(stripTypeScriptTypes(
  `${presentation}\nclass Page {${index.slice(start, end)}}\n({ Page, downloadErrorLabel });`
), { DownloadTaskStatus: states, $r: (key, name) => name ? `${key}:${name}` : key });

function task(status, progress = 0) {
  return { id: 'download', fileName: 'file.dmg', status, progress };
}

function page() {
  const value = new Page();
  value.downloadTasks = [];
  value.toasts = [];
  value.showToast = message => value.toasts.push(message);
  return value;
}

test('new downloads provide an immediate entry and update it through completion exactly once', () => {
  const value = page();
  value.downloadListener([task(states.Pending)]);
  assert.equal(value.downloadNotice.status, states.Pending);
  value.downloadListener([task(states.Downloading, 45)]);
  assert.equal(value.downloadNotice.progress, 45);
  assert.equal(value.toasts.length, 0);
  value.downloadListener([task(states.Completed, 100)]);
  assert.equal(value.downloadNotice.status, states.Completed);
  assert.deepEqual(value.toasts, ['app.string.download_completed_file:file.dmg']);
  value.downloadListener([task(states.Completed, 100)]);
  assert.equal(value.toasts.length, 1);
});

test('dismissed progress stays dismissed until completion or failure requires attention', () => {
  const value = page();
  value.downloadListener([task(states.Downloading)]);
  value.downloadNotice = undefined;
  value.downloadListener([task(states.Downloading, 55)]);
  assert.equal(value.downloadNotice, undefined);
  value.downloadListener([task(states.Failed, 55)]);
  assert.equal(value.downloadNotice.status, states.Failed);
  assert.deepEqual(value.toasts, ['app.string.download_failed_file:file.dmg']);
  value.downloadListener([task(states.Pending)]);
  assert.equal(value.downloadNotice.status, states.Pending);
});

test('removing a task clears its quick entry without replaying old completed tasks', () => {
  const value = page();
  value.downloadListener([task(states.Completed, 100)]);
  assert.equal(value.downloadNotice, undefined);
  assert.equal(value.toasts.length, 0);
  value.downloadListener([task(states.Pending)]);
  value.downloadListener([]);
  assert.equal(value.downloadNotice, undefined);
});

test('download errors distinguish storage, network and expired links', () => {
  assert.equal(downloadErrorLabel('storage'), 'app.string.download_error_storage');
  assert.equal(downloadErrorLabel('22'), 'app.string.download_error_network');
  assert.equal(downloadErrorLabel('34'), 'app.string.download_error_link');
  assert.equal(downloadErrorLabel('3'), 'app.string.download_error_space');
});
