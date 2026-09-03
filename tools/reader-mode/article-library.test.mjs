import assert from 'node:assert/strict';
import test from 'node:test';
import { chromium } from 'playwright';
import { productionCaptureScript } from './reader-core-source.mjs';
import { loadEts } from './ets-module.mjs';

const models = loadEts('entry/src/main/ets/models/ArticleCaptureModels.ets');
const navigation = loadEts('entry/src/main/ets/services/OfflineArticleNavigation.ets');
const scripts = loadEts('entry/src/main/ets/services/ArticleReaderScripts.ets');
const exporting = loadEts('entry/src/main/ets/services/ArticleExportService.ets', {
  '@kit.AbilityKit': {}, '@kit.ArkTS': {}, '@ohos.file.fs': {}, '@ohos.file.picker': {}
}).ArticleExportService;
const article = { id:'article-1-1', title:'Offline test', sourceUrl:'https://example.test/article',
  canonicalUrl:'https://example.test/article', author:'Author', tags:[], failure:0 };
const valid = { title:'Title', author:'', canonicalUrl:article.sourceUrl, sourceUrl:article.sourceUrl,
  text:'A complete short article.', html:'<article>A complete short article.</article>',
  markdown:'A complete short article.', images:[], readerMetrics:{ result:'complete' } };

test('accepts both ArkWeb JSON string and browser object serialization', () => {
  for (const raw of [JSON.stringify(valid), JSON.stringify(JSON.stringify(valid))]) {
    const snapshot = models.parseArticleCapture(raw);
    assert.equal(snapshot.canonicalUrl, article.canonicalUrl);
    assert.equal(models.articleCaptureReadable(snapshot), true);
  }
  for (const raw of ['', 'null', '[]', '{}', '"invalid"']) assert.throws(() => models.parseArticleCapture(raw));
  assert.equal(models.articleCaptureReadable({ ...valid, quality:'unavailable' }), false);
});

async function inBrowser(run) {
  const browser = await chromium.launch({headless:true, ...(process.env.ARTICLE_TEST_BROWSER ?
    {channel:process.env.ARTICLE_TEST_BROWSER} : {})});
  try { await run(await browser.newPage()); } finally { await browser.close(); }
}

test('captures short articles, real lazy images, safe links and sanitized root', async () => {
  await inBrowser(async page => {
    await page.setContent('<article onpointerover="window.unsafe=true"><h1>Short article</h1>' +
      '<p>A short but meaningful complete article with practical advice.</p>' +
      '<img src="https://example.test/placeholder.gif" data-src="https://example.test/actual.jpg">' +
      '<a href="javascript:alert(1)">unsafe link</a><script>void 0</script></article>');
    const snapshot = JSON.parse(await page.evaluate(await productionCaptureScript()));
    assert.equal(snapshot.readerMetrics.result, 'complete');
    assert.equal(snapshot.images[0].url, 'https://example.test/actual.jpg');
    assert.ok(!snapshot.html.includes('onpointerover'));
    assert.ok(!snapshot.html.includes('javascript:'));
    assert.ok(!snapshot.html.includes('<script'));
  });
});

test('offline document renders images and preserves selection/highlight across inline markup', async () => {
  await inBrowser(async page => {
    const requests = [];
    await page.route('**/*', route => { requests.push(route.request().url()); return route.abort(); });
    const html = exporting.standaloneHtmlDocument(article,
      '<article onpointerover="window.unsafe=true"><p>Read <strong>this useful</strong> article now.</p>' +
      '<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==">' +
      '<img src="https://example.test/tracker"><script>window.unsafe=true</script></article>');
    await page.setContent(html);
    assert.equal(await page.locator('#article-content img').first().evaluate(img => img.complete && img.naturalWidth>0), true);
    await page.locator('#article-content article').hover();
    assert.equal(await page.evaluate(() => window.unsafe), undefined);
    assert.equal(requests.length, 0);
    const highlight = { id:'highlight-1',textQuote:'this useful article',prefix:'Read ',suffix:' now.' };
    assert.equal(await page.evaluate(scripts.articleHighlightScript([highlight],highlight.id)),true);
    assert.equal((await page.locator('mark').allTextContents()).join(''),'this useful article');
    await page.evaluate(scripts.articleHighlightScript([]));
    assert.equal(await page.locator('mark').count(),0);
    await page.evaluate(() => {
      const range = document.createRange();range.selectNodeContents(document.querySelector('strong'));
      window.getSelection().removeAllRanges();window.getSelection().addRange(range);
    });
    const selection = JSON.parse(await page.evaluate(scripts.ARTICLE_SELECTION_SCRIPT));
    assert.equal(selection.quote,'this useful');
    assert.ok(selection.text.includes('this useful article'));
  });
});

test('Markdown and HTML embed saved assets without retaining private image paths', async () => {
  const service = loadEts('entry/src/main/ets/services/ArticleExportService.ets', {
    '@kit.AbilityKit': {}, '@kit.ArkTS': {util:{Base64Helper:class {encodeToStringSync(){return 'AQID';}}}},
    '@ohos.file.fs': {OpenMode:{READ_ONLY:1},statSync:()=>({size:3}),openSync:()=>({fd:1}),readSync:()=>3,closeSync(){}},
    '@ohos.file.picker': {}
  }).ArticleExportService;
  const markdown = await service.inlineLocalImages('![image](images/image-0.png)', '/isolated/images');
  assert.equal(markdown,'![image](data:image/png;base64,AQID)');
});

test('image limits and denied image requests are counted as incomplete saves', async () => {
  let status = 200;
  const store = loadEts('entry/src/main/ets/services/ArticleImageStore.ets', {
    '@kit.NetworkKit': {http:{RequestMethod:{GET:0},HttpDataType:{ARRAY_BUFFER:0},
      createHttp:()=>({request:async()=>({responseCode:status,result:new Uint8Array([1,2,3]).buffer}),destroy(){}})}},
    '@ohos.file.fs':{OpenMode:{CREATE:1,READ_WRITE:2,TRUNC:4},open:async()=>({fd:1}),write:async()=>3,close:async()=>{}}
  }).ArticleImageStore;
  const images=Array.from({length:32},(_,index)=>({index,url:`https://example.test/${index}.png`,fileName:`image-${index}.png`}));
  const limited=await store.persist(images,'/isolated/images');
  assert.equal(limited.savedCount,30);assert.equal(limited.failedCount,2);
  status=403;
  const denied=await store.persist(images.slice(0,1),'/isolated/images');
  assert.equal(denied.savedCount,0);assert.equal(denied.failedCount,1);
});

test('capture waits for delayed content and a stable snapshot', async () => {
  const service=loadEts('entry/src/main/ets/services/ArticleCaptureService.ets',{
    '@kit.ArkWeb':{},'../constants/AppConstants':{ARTICLE_CAPTURE_SCRIPT:'capture'}
  }).ArticleCaptureService;
  let calls=0;
  const result=await service.capture({runJavaScript:async()=>{
    calls++;
    return JSON.stringify(JSON.stringify(calls===1 ? {...valid,text:'',html:'',markdown:'',readerMetrics:{result:'unavailable'}} : valid));
  }});
  assert.equal(calls,3);assert.equal(result.quality,'complete');
});

test('a stalled ArkWeb evaluation fails within the bounded capture timeout', async () => {
  const service=loadEts('entry/src/main/ets/services/ArticleCaptureService.ets',{
    '@kit.ArkWeb':{},'../constants/AppConstants':{ARTICLE_CAPTURE_SCRIPT:'capture'}
  }).ArticleCaptureService;
  await assert.rejects(service.capture({runJavaScript:()=>new Promise(()=>{})}), /timed out/);
});

test('offline reader allows one native HTML load but blocks page data links and frames', () => {
  const policy=new navigation.OfflineArticleNavigation();
  const native='data:text/html;charset=UTF-8;base64,';
  assert.equal(policy.allowInternal(native,true),false);
  policy.beginDocument();
  assert.equal(policy.allowInternal(native,false),false);
  assert.equal(policy.allowInternal('data:text/javascript,alert(1)',true),false);
  assert.equal(policy.allowInternal('https://example.test/',true),false);
  assert.equal(policy.allowInternal(native,true),true);
  assert.equal(policy.allowInternal(native,true),false);
  policy.beginDocument();policy.finishDocument();
  assert.equal(policy.allowInternal(native,true),false);
});
