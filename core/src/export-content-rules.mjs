import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compileContentRules } from './content-rules.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(here, '../..');
export const rulesDirectory = path.join(repositoryRoot, 'core/rules');
const adsDirectory = path.join(
  repositoryRoot,
  'ohos/entry/src/main/resources/rawfile/ads'
);

const LISTS = [
  { id: 'supplement', file: 'dolphin-supplement.txt', maxRules: 50000 },
  { id: 'easylistchina', file: 'easylistchina.txt', maxRules: 50000 },
  { id: 'easylist', file: 'easylist.txt', maxRules: 50000 }
];

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export async function exportedSnapshot() {
  const files = {};
  const manifestLists = [];
  const androidNetwork = [];
  for (const list of LISTS) {
    const source = await readFile(path.join(adsDirectory, list.file), 'utf8');
    const compiled = compileContentRules(source, { maxRules: list.maxRules });
    const json = `${JSON.stringify(compiled.rules)}\n`;
    const name = `${list.id}.json`;
    files[name] = json;
    manifestLists.push({
      id: list.id,
      file: name,
      sha256: sha256(json),
      count: compiled.rules.length,
      truncated: compiled.truncated,
      network: compiled.parsed.network.length,
      cosmetic: compiled.parsed.cosmetic.length,
      skipped: compiled.parsed.skipped.length
    });
    for (const rule of compiled.parsed.network) {
      if (androidNetwork.length >= 50000) {
        break;
      }
      androidNetwork.push({ host: rule.host, path: rule.path });
    }
  }
  const androidJson = `${JSON.stringify(androidNetwork)}\n`;
  files['android-network.json'] = androidJson;
  files['manifest.json'] = `${JSON.stringify({
    source: 'ohos/entry/src/main/resources/rawfile/ads',
    lists: manifestLists,
    androidNetwork: {
      file: 'android-network.json',
      sha256: sha256(androidJson),
      count: androidNetwork.length
    }
  }, null, 2)}\n`;
  return files;
}

export async function writeExportedRules() {
  await mkdir(rulesDirectory, { recursive: true });
  const files = await exportedSnapshot();
  const written = [];
  for (const [fileName, content] of Object.entries(files)) {
    await writeFile(path.join(rulesDirectory, fileName), content);
    written.push(fileName);
  }
  return written;
}

export async function checkExportedRules() {
  const expected = await exportedSnapshot();
  const drift = [];
  for (const [fileName, content] of Object.entries(expected)) {
    let current = '';
    try {
      current = await readFile(path.join(rulesDirectory, fileName), 'utf8');
    } catch (_error) {
      drift.push(`${fileName}: missing`);
      continue;
    }
    if (current !== content) {
      drift.push(`${fileName}: stale`);
    }
  }
  return drift;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const checkOnly = process.argv.includes('--check');
  if (checkOnly) {
    const drift = await checkExportedRules();
    if (drift.length > 0) {
      console.error(`core/rules is out of date:\n${drift.map((line) => `  ${line}`).join('\n')}`);
      console.error('Run: cd core && npm run export-rules');
      process.exit(1);
    }
    console.log('core/rules matches bundled filter lists');
  } else {
    const written = await writeExportedRules();
    console.log(`wrote ${written.length} files to core/rules`);
  }
}
