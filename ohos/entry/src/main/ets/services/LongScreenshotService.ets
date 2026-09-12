import { image } from '@kit.ImageKit';
import { webview } from '@kit.ArkWeb';
import { Logger } from '../utils/Logger';

const TAG: string = 'LongScreenshotService';
export const MAX_LONG_SCREENSHOT_SCREENS: number = 40;
export const SCREENSHOT_RENDER_WAIT_MS_READER: number = 150;
export const SCREENSHOT_RENDER_WAIT_MS_NORMAL: number = 180;

export interface PageMetrics {
  totalHeight: number;
  viewportHeight: number;
  viewportWidth: number;
  scrollY: number;
  dpr: number;
}

export interface ScrollSlice {
  scrollY: number;
  clipTopRatio: number;
  clipHeightRatio: number;
}

export const PAGE_METRICS_SCRIPT: string = `
(function() {
  var body = document.body;
  var html = document.documentElement;
  var scrollingEl = document.scrollingElement;
  var reader = document.getElementById('__mb-reader');
  var main = document.querySelector('main, article, [role="main"], #app, #root, .article');
  var height = Math.max(
    body ? body.scrollHeight : 0,
    body ? body.offsetHeight : 0,
    html ? html.clientHeight : 0,
    html ? html.scrollHeight : 0,
    html ? html.offsetHeight : 0,
    scrollingEl ? scrollingEl.scrollHeight : 0,
    scrollingEl ? scrollingEl.offsetHeight : 0,
    reader ? reader.scrollHeight : 0,
    reader ? reader.offsetHeight : 0,
    main ? main.scrollHeight : 0,
    main ? main.offsetHeight : 0
  );
  var viewportHeight = window.innerHeight || (html ? html.clientHeight : 1);
  var viewportWidth = window.innerWidth || (html ? html.clientWidth : 1);
  var scrollY = window.scrollY || window.pageYOffset || (scrollingEl ? scrollingEl.scrollTop : 0) || (html ? html.scrollTop : 0) || (body ? body.scrollTop : 0);
  return JSON.stringify({
    totalHeight: height,
    viewportHeight: viewportHeight,
    viewportWidth: viewportWidth,
    scrollY: scrollY,
    dpr: window.devicePixelRatio || 1
  });
})()
`;

export const PAGE_PREPARE_SCRIPT: string = `
(function() {
  var style = document.getElementById('__zhuo_long_shot_style');
  if (!style) {
    style = document.createElement('style');
    style.id = '__zhuo_long_shot_style';
    style.textContent = '::-webkit-scrollbar { display: none !important; } html, body { scroll-behavior: auto !important; }';
    if (document.head) {
      document.head.appendChild(style);
    }
  }
  var all = document.querySelectorAll('*');
  var vh = window.innerHeight || 1;
  var vw = window.innerWidth || 1;
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    if (el.id === '__mb-reader' || el.tagName === 'BODY' || el.tagName === 'HTML') continue;
    try {
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') {
        var rect = el.getBoundingClientRect();
        // Only hide small overlay banners, sticky headers, floating navbars (not large scroll containers)
        if (rect.height < vh * 0.35 || rect.width < vw * 0.35) {
          el.setAttribute('data-zhuo-orig-visibility', el.style.visibility || '');
          el.style.setProperty('visibility', 'hidden', 'important');
        }
      }
    } catch (e) {}
  }
  return 'prepared';
})()
`;

export const PAGE_RESTORE_SCRIPT: string = `
(function() {
  var style = document.getElementById('__zhuo_long_shot_style');
  if (style && style.parentNode) {
    style.parentNode.removeChild(style);
  }
  var elements = document.querySelectorAll('[data-zhuo-orig-visibility]');
  for (var i = 0; i < elements.length; i++) {
    var el = elements[i];
    var orig = el.getAttribute('data-zhuo-orig-visibility');
    if (orig && orig.length > 0) {
      el.style.visibility = orig;
    } else {
      el.style.removeProperty('visibility');
    }
    el.removeAttribute('data-zhuo-orig-visibility');
  }
  return 'restored';
})()
`;

export function parsePageMetrics(raw: string): PageMetrics | undefined {
  try {
    const unescaped: string = raw.startsWith('"') && raw.endsWith('"') ? JSON.parse(raw) as string : raw;
    const parsed: PageMetrics = JSON.parse(unescaped) as PageMetrics;
    if (parsed && typeof parsed.totalHeight === 'number' && typeof parsed.viewportHeight === 'number') {
      return parsed;
    }
  } catch (error) {
    Logger.warn(TAG, `Failed to parse page metrics: \${String(error)}`);
  }
  return undefined;
}

export function computeScrollSlices(
  totalHeight: number,
  viewportHeight: number,
  maxScreens: number = MAX_LONG_SCREENSHOT_SCREENS
): ScrollSlice[] {
  if (viewportHeight <= 0 || totalHeight <= viewportHeight) {
    return [{ scrollY: 0, clipTopRatio: 0, clipHeightRatio: 1.0 }];
  }

  const slices: ScrollSlice[] = [];
  const fullScreens: number = Math.floor(totalHeight / viewportHeight);
  const remainder: number = totalHeight % viewportHeight;

  let count: number = 0;
  for (let i = 0; i < fullScreens && count < maxScreens; i++) {
    slices.push({
      scrollY: i * viewportHeight,
      clipTopRatio: 0,
      clipHeightRatio: 1.0
    });
    count++;
  }

  if (remainder > 0 && count < maxScreens) {
    slices.push({
      scrollY: Math.max(0, totalHeight - viewportHeight),
      clipTopRatio: (viewportHeight - remainder) / viewportHeight,
      clipHeightRatio: remainder / viewportHeight
    });
  }

  return slices.length > 0 ? slices : [{ scrollY: 0, clipTopRatio: 0, clipHeightRatio: 1.0 }];
}

export async function stitchPixelMaps(
  slices: ScrollSlice[],
  pixelMaps: image.PixelMap[]
): Promise<image.PixelMap | undefined> {
  if (pixelMaps.length === 0) {
    return undefined;
  }
  if (pixelMaps.length === 1) {
    return pixelMaps[0];
  }

  try {
    const firstInfo: image.ImageInfo = await pixelMaps[0].getImageInfo();
    const width: number = firstInfo.size.width;
    const singleHeight: number = firstInfo.size.height;
    if (width <= 0 || singleHeight <= 0) {
      return pixelMaps[0];
    }

    const sliceHeights: number[] = [];
    const sliceTops: number[] = [];
    let totalPhysicalHeight: number = 0;

    for (let i = 0; i < slices.length; i++) {
      const s: ScrollSlice = slices[i];
      const top: number = Math.round(singleHeight * s.clipTopRatio);
      const h: number = Math.min(singleHeight - top, Math.round(singleHeight * s.clipHeightRatio));
      sliceTops.push(top);
      sliceHeights.push(h);
      totalPhysicalHeight += h;
    }

    if (totalPhysicalHeight <= 0) {
      return pixelMaps[0];
    }

    const totalBuffer: ArrayBuffer = new ArrayBuffer(width * totalPhysicalHeight * 4);
    const dstBytes: Uint8Array = new Uint8Array(totalBuffer);
    const singleBuffer: ArrayBuffer = new ArrayBuffer(width * singleHeight * 4);
    const srcBytes: Uint8Array = new Uint8Array(singleBuffer);

    let currentDstRow: number = 0;
    for (let i = 0; i < pixelMaps.length; i++) {
      const pm: image.PixelMap = pixelMaps[i];
      const sliceTop: number = sliceTops[i] ?? 0;
      const sliceH: number = sliceHeights[i] ?? singleHeight;

      await pm.readPixelsToBuffer(singleBuffer);

      const bytesPerRow: number = width * 4;
      for (let row = 0; row < sliceH; row++) {
        const srcOffset: number = (sliceTop + row) * bytesPerRow;
        const dstOffset: number = (currentDstRow + row) * bytesPerRow;
        if (srcOffset + bytesPerRow <= srcBytes.length && dstOffset + bytesPerRow <= dstBytes.length) {
          dstBytes.set(srcBytes.subarray(srcOffset, srcOffset + bytesPerRow), dstOffset);
        }
      }
      currentDstRow += sliceH;
    }

    const result: image.PixelMap = await image.createPixelMap(totalBuffer, {
      size: { width: width, height: totalPhysicalHeight },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
    return result;
  } catch (error) {
    Logger.error(TAG, `Failed to stitch pixel maps: \${String(error)}`);
    return pixelMaps[0];
  }
}

export class LongScreenshotService {
  /**
   * Captures a full scrollable view of the page, in reader mode or normal web page.
   * Restores original scroll position and DOM styles afterwards.
   */
  static async capture(
    controller: webview.WebviewController,
    snapshotGetter: () => Promise<image.PixelMap>,
    runScript: (controller: webview.WebviewController, script: string) => Promise<string>,
    isReader: boolean = false
  ): Promise<image.PixelMap> {
    let initialScrollY: number = 0;
    let isPrepared: boolean = false;
    const waitMs: number = isReader ? SCREENSHOT_RENDER_WAIT_MS_READER : SCREENSHOT_RENDER_WAIT_MS_NORMAL;

    try {
      const metricsRaw: string = await runScript(controller, PAGE_METRICS_SCRIPT);
      const metrics: PageMetrics | undefined = parsePageMetrics(metricsRaw);

      if (metrics === undefined || metrics.totalHeight <= metrics.viewportHeight) {
        return await snapshotGetter();
      }

      let currentTotalHeight: number = metrics.totalHeight;
      let slices: ScrollSlice[] = computeScrollSlices(currentTotalHeight, metrics.viewportHeight, MAX_LONG_SCREENSHOT_SCREENS);

      if (slices.length <= 1) {
        return await snapshotGetter();
      }

      await runScript(controller, PAGE_PREPARE_SCRIPT);
      isPrepared = true;

      const capturedShots: image.PixelMap[] = [];
      for (let i = 0; i < slices.length; i++) {
        const slice: ScrollSlice = slices[i];

        // 1. Native ArkWeb controller scroll
        try {
          controller.scrollTo(0, slice.scrollY);
        } catch (scrollErr) {
          Logger.warn(TAG, `Native controller.scrollTo failed: ${String(scrollErr)}`);
        }

        // 2. Multi-target DOM scroll script
        const scrollScript: string = `(function() {
          var y = ${slice.scrollY};
          try { window.scrollTo(0, y); } catch(e) {}
          try { if (document.scrollingElement) document.scrollingElement.scrollTop = y; } catch(e) {}
          try { if (document.documentElement) document.documentElement.scrollTop = y; } catch(e) {}
          try { if (document.body) document.body.scrollTop = y; } catch(e) {}
          var r = document.getElementById('__mb-reader');
          if (r) { try { r.scrollTop = y; } catch(e) {} }
          return (window.scrollY || (document.scrollingElement ? document.scrollingElement.scrollTop : 0) || (document.documentElement ? document.documentElement.scrollTop : 0));
        })()`;
        await runScript(controller, scrollScript);

        // 3. Wait for hardware surface rasterization and buffer swap
        await LongScreenshotService.delay(waitMs);

        // 4. Capture snapshot
        const shot: image.PixelMap = await snapshotGetter();
        capturedShots.push(shot);

        // 5. Check if page height expanded due to lazy loading
        if (i < slices.length - 1 && (i % 3 === 0 || i === slices.length - 2)) {
          try {
            const currentMetricsRaw: string = await runScript(controller, PAGE_METRICS_SCRIPT);
            const currentMetrics: PageMetrics | undefined = parsePageMetrics(currentMetricsRaw);
            if (currentMetrics !== undefined && currentMetrics.totalHeight > currentTotalHeight + 50) {
              currentTotalHeight = currentMetrics.totalHeight;
              slices = computeScrollSlices(currentTotalHeight, metrics.viewportHeight, MAX_LONG_SCREENSHOT_SCREENS);
            }
          } catch (_e) {
            // Ignored
          }
        }
      }

      const stitched: image.PixelMap | undefined = await stitchPixelMaps(slices, capturedShots);
      return stitched ?? capturedShots[0];
    } catch (error) {
      Logger.warn(TAG, `Long screenshot capture encountered error, falling back: ${String(error)}`);
      return await snapshotGetter();
    } finally {
      if (isPrepared) {
        try {
          await runScript(controller, PAGE_RESTORE_SCRIPT);
        } catch (_e) {
          // Ignored
        }
      }
      try {
        controller.scrollTo(0, initialScrollY);
      } catch (_e) {}
      try {
        await runScript(
          controller,
          `(function(){ var y = ${initialScrollY}; try{window.scrollTo(0,y);}catch(e){} if(document.scrollingElement)document.scrollingElement.scrollTop=y; })();`
        );
      } catch (_e) {
        // Ignored
      }
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
