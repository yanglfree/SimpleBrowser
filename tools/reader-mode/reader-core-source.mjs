import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(toolDirectory, '../..');

async function constantsSource() {
  const constantsPath = path.join(repositoryRoot, 'entry/src/main/ets/constants/AppConstants.ets');
  return readFile(constantsPath, 'utf8');
}

export async function productionExtractorScript() {
  const source = await constantsSource();
  const prefix = 'export const READER_EXTRACTION_CORE_SCRIPT: string = `';
  const start = source.indexOf(prefix);
  assert.notEqual(start, -1, 'production extraction core must be exported from AppConstants.ets');
  const contentStart = start + prefix.length;
  const contentEnd = source.indexOf('\n`;\n', contentStart);
  assert.notEqual(contentEnd, -1, 'production extraction core must have a stable template boundary');
  const templateSource = source.slice(contentStart, contentEnd);
  return Function(`return \`${templateSource}\`;`)();
}

export async function productionReaderApplyScript(fontSize = 17, lineHeight = 205) {
  const source = await constantsSource();
  const functionStart = source.indexOf('export function readerApplyScript(');
  assert.notEqual(functionStart, -1);
  const prefix = '  return `';
  const contentStart = source.indexOf(prefix, functionStart) + prefix.length;
  const contentEnd = source.indexOf('`;\n}', contentStart);
  assert.notEqual(contentEnd, -1);
  const templateSource = source.slice(contentStart, contentEnd);
  const core = await productionExtractorScript();
  return Function(
    'READER_EXTRACTION_CORE_SCRIPT', 'fontSize', 'lineHeightRatio',
    'paperBackground', 'bodyColor', 'titleColor', 'accentColor',
    `return \`${templateSource}\`;`
  )(core, fontSize, (lineHeight / 100).toFixed(2), '#ffffff', '#222222', '#111111', '#2e6b5c');
}

export async function productionCaptureScript() {
  const source = await constantsSource();
  const prefix = 'export const ARTICLE_CAPTURE_SCRIPT: string = `';
  const contentStart = source.indexOf(prefix) + prefix.length;
  assert.ok(contentStart >= prefix.length);
  const contentEnd = source.indexOf('`;\n\n/** Counts visible text matches', contentStart);
  assert.notEqual(contentEnd, -1);
  const templateSource = source.slice(contentStart, contentEnd);
  return Function('READER_EXTRACTION_CORE_SCRIPT', `return \`${templateSource}\`;`)(
    await productionExtractorScript()
  );
}

export async function productionReaderExitScript() {
  const source = await constantsSource();
  const prefix = 'export const READER_EXIT_SCRIPT: string = `';
  const contentStart = source.indexOf(prefix) + prefix.length;
  assert.ok(contentStart >= prefix.length);
  const contentEnd = source.indexOf('`;\n\n/** Extracts the best readable article', contentStart);
  assert.notEqual(contentEnd, -1);
  return Function(`return \`${source.slice(contentStart, contentEnd)}\`;`)();
}
