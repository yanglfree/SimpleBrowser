import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { prepareRetention } from './prepare-retention.mjs';

test('retention metadata and checksum refer to the actual immutable remote filename', () => {
  const directory = mkdtempSync(join(tmpdir(), 'retention-test-'));
  try {
    const artifact = 'Example-1.0.1+1000001.hap';
    const bytes = Buffer.from('signed fixture');
    const hash = createHash('sha256').update(bytes).digest('hex');
    writeFileSync(join(directory, artifact), bytes);
    writeFileSync(join(directory, 'release-metadata.json'), JSON.stringify({ artifact, sourceSha: 'a'.repeat(40) }));
    writeFileSync(join(directory, 'SHA256SUMS'), `${hash}  ${artifact}\n`);
    const target = prepareRetention(directory, '123-2');
    const metadata = JSON.parse(readFileSync(join(target, '123-2-release-metadata.json')));
    assert.equal(metadata.sourceSha, 'a'.repeat(40));
    assert.equal(metadata.artifact, `123-2-${artifact}`);
    assert.deepEqual(readFileSync(join(target, metadata.artifact)), bytes);
    assert.equal(readFileSync(join(target, '123-2-SHA256SUMS'), 'utf8'), `${hash}  ${metadata.artifact}\n`);
    assert.throws(() => prepareRetention(directory, '../escape'));
    writeFileSync(join(directory, artifact), 'corrupt');
    assert.throws(() => prepareRetention(directory, '123-3'));
  } finally { rmSync(directory, { recursive: true }); }
});

test('retention preserves a store App Pack with an independent checksum', () => {
  const directory = mkdtempSync(join(tmpdir(), 'retention-store-test-'));
  try {
    const artifact = 'Example-1.0.1+1000001.hap';
    const storeArtifact = 'Example-1.0.1+1000001.app';
    const bytes = Buffer.from('signed fixture');
    const storeBytes = Buffer.from('store wrapper fixture');
    const hash = createHash('sha256').update(bytes).digest('hex');
    const storeHash = createHash('sha256').update(storeBytes).digest('hex');
    writeFileSync(join(directory, artifact), bytes);
    writeFileSync(join(directory, storeArtifact), storeBytes);
    writeFileSync(join(directory, 'release-metadata.json'), JSON.stringify({
      artifact, storeArtifact, storeSha256: storeHash, sourceSha: 'a'.repeat(40),
    }));
    writeFileSync(join(directory, 'SHA256SUMS'), `${hash}  ${artifact}\n`);
    writeFileSync(join(directory, 'STORE_SHA256SUMS'), `${storeHash}  ${storeArtifact}\n`);
    const target = prepareRetention(directory, '456-1');
    const metadata = JSON.parse(readFileSync(join(target, '456-1-release-metadata.json')));
    assert.equal(metadata.storeArtifact, `456-1-${storeArtifact}`);
    assert.equal(metadata.storeSha256, storeHash);
    assert.deepEqual(readFileSync(join(target, metadata.storeArtifact)), storeBytes);
    assert.equal(readFileSync(join(target, '456-1-STORE_SHA256SUMS'), 'utf8'), `${storeHash}  ${metadata.storeArtifact}\n`);
    writeFileSync(join(directory, 'STORE_SHA256SUMS'), `${'0'.repeat(64)}  ${storeArtifact}\n`);
    assert.throws(() => prepareRetention(directory, '456-2'));
  } finally { rmSync(directory, { recursive: true }); }
});
