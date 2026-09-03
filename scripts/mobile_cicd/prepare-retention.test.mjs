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
