import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function prepareRetention(directory, releaseId) {
  assert.match(releaseId, /^[0-9]+-[0-9]+$/);
  const metadata = JSON.parse(readFileSync(join(directory, 'release-metadata.json'), 'utf8'));
  assert.match(metadata.artifact, /^[A-Za-z0-9][A-Za-z0-9._+-]*\.hap$/);
  const bytes = readFileSync(join(directory, metadata.artifact));
  const hash = createHash('sha256').update(bytes).digest('hex');
  assert.equal(readFileSync(join(directory, 'SHA256SUMS'), 'utf8').trim(), `${hash}  ${metadata.artifact}`, 'Retention input checksum mismatch');
  const target = join(directory, 'retained');
  mkdirSync(target, { recursive: true });
  metadata.artifact = `${releaseId}-${metadata.artifact}`;
  metadata.retentionId = releaseId;
  writeFileSync(join(target, metadata.artifact), bytes);
  writeFileSync(join(target, `${releaseId}-SHA256SUMS`), `${hash}  ${metadata.artifact}\n`);
  if (metadata.storeArtifact !== undefined) {
    assert.match(metadata.storeArtifact, /^[A-Za-z0-9][A-Za-z0-9._+-]*\.app$/);
    const storeBytes = readFileSync(join(directory, metadata.storeArtifact));
    const storeHash = createHash('sha256').update(storeBytes).digest('hex');
    assert.equal(metadata.storeSha256, storeHash, 'Store artifact metadata checksum mismatch');
    assert.equal(readFileSync(join(directory, 'STORE_SHA256SUMS'), 'utf8').trim(), `${storeHash}  ${metadata.storeArtifact}`, 'Store retention input checksum mismatch');
    metadata.storeArtifact = `${releaseId}-${metadata.storeArtifact}`;
    writeFileSync(join(target, metadata.storeArtifact), storeBytes);
    writeFileSync(join(target, `${releaseId}-STORE_SHA256SUMS`), `${storeHash}  ${metadata.storeArtifact}\n`);
  }
  writeFileSync(join(target, `${releaseId}-release-metadata.json`), JSON.stringify(metadata) + '\n');
  return target;
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  console.log(prepareRetention(process.argv[2], process.argv[3]));
}
