import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { chromium } from 'playwright';
import {
  productionBlockedLinkGuardScript,
  productionCaptureScript,
  productionExtractorScript,
  productionReaderApplyScript,
  productionReaderExitScript,
  toolDirectory
} from './reader-core-source.mjs';

test('shared navigation guard preserves cancellation, new windows, and native hash history', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext();
    await context.route('https://fixture.test/**', route => route.fulfill({
      contentType: 'text/html',
      body: `<!doctype html><html><body>
        <a id="allowed" href="#/analysis">Allowed</a>
        <a id="cancelled" href="#/blocked">Cancelled</a>
        <a id="new-window" href="#/popup" target="_blank">Popup</a>
        <script>
          window.hashEvents = [];
          window.addEventListener('hashchange', () => window.hashEvents.push(location.hash));
          document.getElementById('cancelled').addEventListener('click', event => event.preventDefault());
        </script>
      </body></html>`
    }));
    const page = await context.newPage();
    await page.goto('https://fixture.test/app#/home');
    await page.addScriptTag({ content: await productionBlockedLinkGuardScript() });

    await page.locator('#cancelled').click();
    await page.waitForTimeout(10);
    assert.equal(new URL(page.url()).hash, '#/home');

    const popupPromise = page.waitForEvent('popup');
    await page.locator('#new-window').click();
    const popup = await popupPromise;
    await popup.waitForLoadState('domcontentloaded');
    assert.equal(new URL(page.url()).hash, '#/home');
    assert.equal(new URL(popup.url()).hash, '#/popup');
    await popup.close();

    await page.locator('#allowed').click();
    await page.waitForFunction(() => location.hash === '#/analysis');
    await page.waitForFunction(() => window.hashEvents.length === 1);
    assert.deepEqual(await page.evaluate(() => window.hashEvents), ['#/analysis']);

    await page.goBack();
    await page.waitForFunction(() => location.hash === '#/home');
    await page.goForward();
    await page.waitForFunction(() => location.hash === '#/analysis');
    await page.waitForFunction(() => window.hashEvents.length === 3);
    assert.deepEqual(
      await page.evaluate(() => window.hashEvents),
      ['#/analysis', '#/home', '#/analysis']
    );
  } finally {
    await browser.close();
  }
});

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
    assert.equal(await page.locator('meta[name="viewport"]').count(), 0);
    await page.evaluate(() => {
      const button = document.createElement('button');
      button.id = 'stateful-button';
      button.textContent = 'Continue';
      button.addEventListener('click', () => {
        window.__statefulClickCount = (window.__statefulClickCount || 0) + 1;
      });
      const input = document.createElement('input');
      input.id = 'stateful-input';
      input.value = 'draft preserved by the page';
      document.body.append(button, input);
      window.__originalStatefulButton = button;
    });

    const entered = JSON.parse(await page.evaluate(await productionReaderApplyScript()));
    const firstText = await page.locator('#__mb-reader').innerText();
    assert.equal(entered.status, 'reader');
    assert.equal(entered.result, 'complete');
    assert.ok(firstText.includes('FIRST_ANCHOR'));
    assert.ok(firstText.includes('MIDDLE_ANCHOR'));
    assert.ok(firstText.includes('LAST_ANCHOR'));
    assert.match(
      await page.locator('meta[name="viewport"]').getAttribute('content'),
      /width=device-width/
    );
    assert.equal(await page.locator('#__mb-reader').evaluate(node => getComputedStyle(node).boxSizing), 'border-box');

    const restyled = JSON.parse(await page.evaluate(await productionReaderApplyScript(21, 230)));
    assert.equal(restyled.status, 'reader');
    assert.equal(await page.locator('#__mb-reader').innerText(), firstText);

    assert.equal(await page.evaluate(await productionReaderExitScript()), 'restored');
    assert.equal(await page.locator('#__mb-reader').count(), 0);
    assert.equal(await page.locator('#js_content').count(), 1);
    assert.equal(await page.locator('meta[name="viewport"]').count(), 0);
    assert.equal(await page.locator('#stateful-input').inputValue(), 'draft preserved by the page');
    assert.equal(
      await page.evaluate(() => document.getElementById('stateful-button') === window.__originalStatefulButton),
      true
    );
    await page.locator('#stateful-button').click();
    assert.equal(await page.evaluate(() => window.__statefulClickCount), 1);
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
