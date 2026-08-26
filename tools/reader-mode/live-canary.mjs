import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { productionExtractorScript, toolDirectory } from './reader-core-source.mjs';

const canaries = JSON.parse(await readFile(path.join(toolDirectory, 'canaries.json'), 'utf8'));
const browser = await chromium.launch({ headless: true });
let failed = false;

try {
  for (const canary of canaries) {
    const page = await browser.newPage({
      userAgent: 'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36'
    });
    try {
      const response = await page.goto(canary.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      if (!response || !response.ok()) throw new Error(`HTTP ${response?.status() ?? 'no-response'}`);
      await page.waitForSelector('#js_content, article, main, [role="main"]', { timeout: 15000 });
      await page.addScriptTag({ content: await productionExtractorScript() });
      const actual = await page.evaluate(() => {
        const extraction = window.__zhuoReaderExtract(document);
        const text = extraction.node ? extraction.node.textContent.replace(/\s+/g, ' ').trim() : '';
        return { result: extraction.result, strategy: extraction.strategy, outputChars: text.length, text };
      });
      const missingAnchors = canary.requiredAnchors.filter(anchor => !actual.text.includes(anchor));
      const passed = actual.result !== 'unavailable' && actual.outputChars >= canary.minimumTextLength &&
        missingAnchors.length === 0;
      failed ||= !passed;
      console.log(JSON.stringify({
        name: canary.name,
        network: 'ok',
        passed,
        result: actual.result,
        strategy: actual.strategy,
        outputChars: actual.outputChars,
        missingAnchors
      }));
    } catch (error) {
      failed = true;
      console.log(JSON.stringify({ name: canary.name, network: 'failed', passed: false, error: String(error) }));
    } finally {
      await page.close();
    }
  }
} finally {
  await browser.close();
}

process.exitCode = failed ? 1 : 0;
