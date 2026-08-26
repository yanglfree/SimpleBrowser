import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { chromium } from 'playwright';
import {
  productionCaptureScript,
  productionExtractorScript,
  productionReaderApplyScript,
  productionReaderExitScript,
  toolDirectory
} from './reader-core-source.mjs';

async function loadFixture(page, slug) {
  const directory = path.join(toolDirectory, 'fixtures', slug);
  const [html, expectedText] = await Promise.all([
    readFile(path.join(directory, 'source.html'), 'utf8'),
    readFile(path.join(directory, 'expected.json'), 'utf8')
  ]);
  await page.setContent(html, { waitUntil: 'domcontentloaded' });
  await page.addScriptTag({ content: await productionExtractorScript() });
  const actual = await page.evaluate(() => {
    const extraction = window.__zhuoReaderExtract(document);
    return {
      ...extraction,
      text: extraction.node ? extraction.node.textContent.replace(/\s+/g, ' ').trim() : ''
    };
  });
  return { actual, expected: JSON.parse(expectedText) };
}

const fixtureSlugs = (await readdir(path.join(toolDirectory, 'fixtures'), { withFileTypes: true }))
  .filter(entry => entry.isDirectory())
  .map(entry => entry.name)
  .sort();

for (const slug of fixtureSlugs) {
  test(`matches reader golden fixture: ${slug}`, async () => {
    const browser = await chromium.launch({ headless: true });
    try {
      const page = await browser.newPage();
      const { actual, expected } = await loadFixture(page, slug);

      assert.equal(actual.result, expected.expectedResult, expected.name);
      assert.equal(actual.strategy, expected.expectedStrategy, expected.name);
      assert.ok(actual.text.length >= expected.minimumTextLength, expected.name);
      assert.ok(actual.paragraphCount >= expected.minimumParagraphs, expected.name);
      assert.ok(actual.imageCount >= expected.minimumImages, expected.name);
      for (const anchor of expected.requiredAnchors) assert.ok(actual.text.includes(anchor), `${expected.name}: ${anchor}`);
      for (const anchor of expected.forbiddenAnchors) assert.ok(!actual.text.includes(anchor), `${expected.name}: ${anchor}`);
    } finally {
      await browser.close();
    }
  });
}

test('returns deterministic extraction for the same frozen DOM', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const first = await loadFixture(page, 'generic-article');
    const second = await loadFixture(page, 'generic-article');
    assert.deepEqual(
      { result: first.actual.result, strategy: first.actual.strategy, text: first.actual.text },
      { result: second.actual.result, strategy: second.actual.strategy, text: second.actual.text }
    );
  } finally {
    await browser.close();
  }
});

test('enters, restyles, and exits reader mode through the production scripts', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const html = await readFile(path.join(toolDirectory, 'fixtures/wechat-long/source.html'), 'utf8');
    await page.setContent(html, { waitUntil: 'domcontentloaded' });

    const entered = JSON.parse(await page.evaluate(await productionReaderApplyScript()));
    const firstText = await page.locator('#__mb-reader').innerText();
    assert.equal(entered.status, 'reader');
    assert.equal(entered.result, 'complete');
    assert.ok(firstText.includes('FIRST_ANCHOR'));
    assert.ok(firstText.includes('MIDDLE_ANCHOR'));
    assert.ok(firstText.includes('LAST_ANCHOR'));

    const restyled = JSON.parse(await page.evaluate(await productionReaderApplyScript(21, 230)));
    assert.equal(restyled.status, 'reader');
    assert.equal(await page.locator('#__mb-reader').innerText(), firstText);

    assert.equal(await page.evaluate(await productionReaderExitScript()), 'restored');
    assert.equal(await page.locator('#__mb-reader').count(), 0);
    assert.equal(await page.locator('#js_content').count(), 1);
  } finally {
    await browser.close();
  }
});

test('offline capture consumes the same production extraction result', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const wechatHtml = await readFile(path.join(toolDirectory, 'fixtures/wechat-long/source.html'), 'utf8');
    await page.setContent(wechatHtml, { waitUntil: 'domcontentloaded' });

    const capture = JSON.parse(await page.evaluate(await productionCaptureScript()));
    assert.ok(capture.text.includes('FIRST_ANCHOR'));
    assert.ok(capture.text.includes('MIDDLE_ANCHOR'));
    assert.ok(capture.text.includes('LAST_ANCHOR'));
    assert.equal(capture.readerMetrics.result, 'complete');
    assert.equal(capture.readerMetrics.strategy, 'site_adapter');

    const genericHtml = await readFile(path.join(toolDirectory, 'fixtures/generic-article/source.html'), 'utf8');
    await page.setContent(genericHtml, { waitUntil: 'domcontentloaded' });
    const genericCapture = JSON.parse(await page.evaluate(await productionCaptureScript()));
    assert.ok(genericCapture.text.includes('MIDDLE_ANCHOR'));
    assert.ok(!genericCapture.text.includes('COMMENT_NOISE'));
  } finally {
    await browser.close();
  }
});
