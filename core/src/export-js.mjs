import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FILE_NAMES, loadStaticScripts, repositoryRoot } from './injected-scripts.mjs';

export const jsDirectory = path.join(repositoryRoot, 'core/js');

export async function exportedSnapshot() {
  const scripts = await loadStaticScripts();
  const files = {};
  for (const [name, fileName] of Object.entries(FILE_NAMES)) {
    const body = scripts[name];
    if (typeof body !== 'string') {
      throw new Error(`missing script ${name}`);
    }
    files[fileName] = `${body.trim()}\n`;
  }
  files['manifest.json'] = `${JSON.stringify({
    source: 'entry/src/main/ets/constants/AppConstants.ets',
    files: Object.values(FILE_NAMES)
  }, null, 2)}\n`;
  return files;
}

export async function writeExportedScripts() {
  await mkdir(jsDirectory, { recursive: true });
  const files = await exportedSnapshot();
  const written = [];
  for (const [fileName, content] of Object.entries(files)) {
    const target = path.join(jsDirectory, fileName);
    await writeFile(target, content);
    written.push(fileName);
  }
  return written;
}

export async function checkExportedScripts() {
  const expected = await exportedSnapshot();
  const drift = [];
  for (const [fileName, content] of Object.entries(expected)) {
    const target = path.join(jsDirectory, fileName);
    let current = '';
    try {
      current = await readFile(target, 'utf8');
    } catch (error) {
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
    const drift = await checkExportedScripts();
    if (drift.length > 0) {
      console.error(`core/js is out of date:\n${drift.map((line) => `  ${line}`).join('\n')}`);
      console.error('Run: cd core && npm run export-js');
      process.exit(1);
    }
    console.log('core/js matches AppConstants.ets');
  } else {
    const written = await writeExportedScripts();
    console.log(`wrote ${written.length} files to core/js`);
  }
}
