import assert from 'node:assert/strict';
import { test } from 'node:test';
import { requestBytes } from './transport.mjs';

const options = { sleep: async () => {}, onRetry: () => {} };
test('retries a connection reset using the same immutable body and headers', async () => {
  let calls = 0;
  const body = Buffer.from('artifact');
  const response = await requestBytes('https://example.test/artifact', { method: 'PUT', body }, {
    ...options, fetchImpl: async (_url, init) => {
      assert.equal(init.body, body);
      assert.equal(init.redirect, 'error');
      if (++calls === 1) throw new TypeError('connection reset');
      return new Response('ok');
    },
  });
  assert.equal(calls, 2);
  assert.equal(await response.text(), 'ok');
});
test('retries interrupted response bodies and retains byte range metadata', async () => {
  let calls = 0;
  const response = await requestBytes('https://example.test/artifact', {}, {
    ...options, fetchImpl: async () => {
      if (++calls === 1) return new Response(new ReadableStream({ start(controller) { controller.error(new TypeError('body reset')); } }));
      return new Response('x', { status: 206, headers: { 'content-range': 'bytes 0-0/3' } });
    },
  });
  assert.equal(calls, 2);
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-range'), 'bytes 0-0/3');
  assert.equal(await response.text(), 'x');
});
test('retries transient service errors but returns authentication errors immediately', async () => {
  let calls = 0;
  const response = await requestBytes('https://example.test/artifact', {}, {
    ...options, fetchImpl: async () => new Response('error', { status: ++calls === 1 ? 503 : 403 }),
  });
  assert.equal(calls, 2);
  assert.equal(response.status, 403);
});
test('stops after the bounded attempt count', async () => {
  let calls = 0;
  await assert.rejects(requestBytes('https://example.test/artifact', {}, {
    ...options, fetchImpl: async () => { calls++; throw new TypeError('offline'); },
  }), TypeError);
  assert.equal(calls, 4);
});
test('preserves HEAD response length without fabricating a body', async () => {
  const response = await requestBytes('https://example.test/artifact', { method: 'HEAD' }, {
    ...options, fetchImpl: async () => new Response(null, { headers: { 'content-length': '20' } }),
  });
  assert.equal(response.headers.get('content-length'), '20');
  assert.equal((await response.arrayBuffer()).byteLength, 0);
});
