import test from 'node:test';
import assert from 'node:assert/strict';
import { PendingPurchaseRecovery, PurchaseRecoveryResult } from '../iap_paywall_kit/src/main/ets/models/PendingPurchaseRecovery.ts';

test('pending recovery retries failures and returns success exactly once', async () => {
  let attempts = 0;
  let errors = 0;
  const result = await new PendingPurchaseRecovery().run(async () => {
    attempts++;
    if (attempts === 1) throw new Error('server unavailable');
    return attempts === 3;
  }, () => errors++, [0, 1, 1]);
  assert.equal(result, PurchaseRecoveryResult.RECOVERED);
  assert.equal(attempts, 3);
  assert.equal(errors, 1);
});

test('pending recovery stops after its retry budget', async () => {
  let attempts = 0;
  const result = await new PendingPurchaseRecovery().run(async () => {
    attempts++;
    return false;
  }, () => {}, [0, 1, 1]);
  assert.equal(result, PurchaseRecoveryResult.EXHAUSTED);
  assert.equal(attempts, 3);
});

test('leaving the page suppresses a late successful response', async () => {
  const recovery = new PendingPurchaseRecovery();
  let complete;
  const run = recovery.run(() => new Promise(resolve => { complete = resolve; }), () => {});
  recovery.cancel();
  complete(true);
  assert.equal(await run, PurchaseRecoveryResult.CANCELLED);
});

test('cancelling a retry delay releases the waiter without another request', async () => {
  const recovery = new PendingPurchaseRecovery();
  let attempts = 0;
  const run = recovery.run(async () => { attempts++; return false; }, () => {}, [0, 10000]);
  await new Promise(resolve => setTimeout(resolve, 5));
  recovery.cancel();
  assert.equal(await run, PurchaseRecoveryResult.CANCELLED);
  assert.equal(attempts, 1);
});
