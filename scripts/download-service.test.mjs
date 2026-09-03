import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const states = { IN_PROGRESS: 0, COMPLETED: 1, CANCELED: 2, INTERRUPTED: 3, PENDING: 4, PAUSED: 5 };
const tick = () => new Promise(setImmediate);

function fixture({ pickerFailure = false } = {}) {
  const source = readFileSync(new URL('../entry/src/main/ets/services/DownloadService.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
  const callbacks = {};
  const resumptions = [];
  const notifications = [];
  const existingPaths = new Set();
  let pickerCalls = 0;
  class Delegate {
    onBeforeDownload(fn) { callbacks.before = fn; }
    onDownloadUpdated(fn) { callbacks.update = fn; }
    onDownloadFinish(fn) { callbacks.finish = fn; }
    onDownloadFailed(fn) { callbacks.fail = fn; }
  }
  const service = runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\nDownloadService;`, {
    Logger: { info() {}, warn() {}, error() {} },
    environment: { getUserDownloadDir() { throw Object.assign(new Error('Capability not supported'), { code: 801 }); } },
    picker: {
      DocumentPickerMode: { DOWNLOAD: 1 },
      DocumentViewPicker: class {
        async save(options) {
          pickerCalls++;
          assert.equal(options.pickerMode, 1);
          if (pickerFailure) throw new Error('Picker failed');
          return ['file://docs/storage/Users/currentUser/Download/ZhuoBrowser'];
        }
      }
    },
    fileUri: {
      FileUri: class { constructor(uri) { this.path = uri.replace('file://docs', ''); } },
      getUriFromPath: path => `file://docs${path}`
    },
    fs: { accessSync: path => existingPaths.has(path), unlinkSync: path => existingPaths.delete(path) },
    notificationManager: {
      ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
      publish: async notification => { notifications.push(notification); }
    },
    webview: {
      WebDownloadDelegate: Delegate,
      WebDownloadState: states,
      WebDownloadItem: { deserialize: data => ({ restored: data }) },
      WebDownloadManager: { setDownloadDelegate() {}, resumeDownload: item => resumptions.push(item) }
    }
  });
  service.configure({ filesDir: '/data/storage/el2/base/files' });
  return { service, callbacks, resumptions, notifications, existingPaths, get pickerCalls() { return pickerCalls; } };
}

function item(id, name = 'QQMusicMac11.9.0Build01.dmg') {
  const value = {
    state: states.IN_PROGRESS, starts: [], pauses: 0, resumes: 0, cancellations: 0, progress: 0,
    getGuid: () => id,
    getSuggestedFileName: () => name,
    getUrl: () => 'https://downloads.example/file.dmg?sign=must-preserve',
    getTotalBytes: () => 101866704,
    getReceivedBytes: () => 1024,
    getCurrentSpeed: () => 1024,
    getPercentComplete() { return this.progress; },
    getState() { return this.state; },
    getLastErrorCode: () => 22,
    getFullPath() { return this.starts.at(-1) ?? ''; },
    serialize: () => new Uint8Array([id.length]),
    start(path) { this.starts.push(path); },
    pause() { this.pauses++; this.state = states.PAUSED; },
    resume() { this.resumes++; this.state = states.IN_PROGRESS; },
    cancel() { this.cancellations++; this.state = states.CANCELED; }
  };
  return value;
}

test('phone downloads use the authorized directory without the unsupported environment API', async () => {
  const f = fixture();
  const native = item('phone');
  f.callbacks.before(native);
  await tick();
  assert.equal(f.service.getTasks()[0].status, 1);
  assert.equal(native.starts[0], '/storage/Users/currentUser/Download/ZhuoBrowser/QQMusicMac11.9.0Build01.dmg');
  assert.equal(f.service.getTasks()[0].url, native.getUrl());
  assert.equal(f.pickerCalls, 1);
});

test('concurrent same-name downloads reserve distinct paths and share directory authorization', async () => {
  const f = fixture();
  const first = item('one');
  const second = item('two');
  f.callbacks.before(first);
  f.callbacks.before(second);
  await tick();
  assert.equal(first.starts.length, 1);
  assert.equal(second.starts.length, 1);
  assert.notEqual(first.starts[0], second.starts[0]);
  assert.equal(f.pickerCalls, 1);
});

test('resume does not depend on pause mutating an earlier native callback snapshot', async () => {
  const f = fixture();
  const native = item('snapshot');
  native.pause = () => { native.pauses++; };
  f.callbacks.before(native);
  await tick();
  assert.equal(native.resumes, 1);
});

test('pause uses the latest callback item and a late progress callback cannot resume it', async () => {
  const f = fixture();
  f.callbacks.before(item('pause'));
  await tick();
  const current = item('pause');
  current.progress = 30;
  f.callbacks.update(current);
  f.service.pause('pause');
  assert.equal(current.pauses, 1);
  current.state = states.IN_PROGRESS;
  f.callbacks.update(current);
  assert.equal(f.service.getTasks()[0].status, 2);
  current.state = states.PAUSED;
  f.service.resume('pause');
  await tick();
  assert.equal(current.resumes, 1);
  assert.equal(f.resumptions.length, 0);
});

test('retry restores the failed native snapshot instead of the original before-download item', async () => {
  const f = fixture();
  f.callbacks.before(item('retry'));
  await tick();
  const failed = item('retry');
  failed.state = states.INTERRUPTED;
  f.callbacks.fail(failed);
  f.service.retry('retry');
  await tick();
  assert.equal(f.resumptions.length, 1);
  assert.deepEqual([...f.resumptions[0].restored], [5]);
});

test('removing an active task cancels native work and releases its queue slot', async () => {
  const f = fixture();
  f.service.setConcurrencyLimit(1);
  const first = item('one');
  const second = item('two');
  f.callbacks.before(first);
  f.callbacks.before(second);
  await tick();
  f.service.remove('one', false);
  await tick();
  assert.equal(first.cancellations, 1);
  assert.equal(second.starts.length, 1);
});

test('picker failure does not leave an invisible native download running', async () => {
  const f = fixture({ pickerFailure: true });
  const native = item('picker');
  f.callbacks.before(native);
  await tick();
  assert.equal(f.service.getTasks()[0].status, 4);
  assert.equal(native.cancellations, 1);
  assert.equal(native.starts.length, 0);
});

test('cancel while choosing a directory cannot start the removed task later', async () => {
  const f = fixture();
  const native = item('removed');
  f.callbacks.before(native);
  f.service.remove('removed', false);
  await tick();
  assert.equal(native.starts.length, 0);
  assert.equal(f.service.getTasks().length, 0);
});
