import { webview } from '@kit.ArkWeb';
import {
  COMPATIBLE_MOBILE_USER_AGENT,
  DESKTOP_USER_AGENT,
  MIN_COMPATIBLE_CHROME_MAJOR
} from '../constants/AppConstants';
import { Logger } from '../utils/Logger';
import { isSameDocumentUrl } from '../utils/UrlUtils';

const TAG: string = 'WebKernelService';

export interface WebKernelCallbacks {
  onPageBegin: (url: string) => void;
  onProgressChange: (progress: number) => void;
  onPageEnd: (url: string) => void;
  onNavigationStateChange: () => void;
  /** Fragment change on the current document — not a new page load. */
  onSameDocumentNavigation: (url: string) => void;
  onError: (url: string, code: number, message: string) => void;
  onSslError: (url: string, code: SslError, chain: Array<Uint8Array>) => void;
  onAlert: (url: string, message: string, result: JsResult) => boolean;
  onConfirm: (url: string, message: string, result: JsResult) => boolean;
  onPrompt: (url: string, message: string, defaultValue: string, result: JsResult) => boolean;
  onBeforeUnload: (url: string, message: string, result: JsResult) => boolean;
  onWindowNew: (targetUrl: string, isUserTrigger: boolean, handler: ControllerHandler) => void;
  onWindowExit: () => void;
  onFullScreenEnter: (handler: FullScreenExitHandler) => void;
  onFullScreenExit: () => void;
  onHttpAuthRequest: (event: OnHttpAuthRequestEvent) => boolean;
  onRenderExited: (reason: number) => void;
}

export interface WebHistoryEntry {
  title: string;
  url: string;
  step: number;
}

export enum WebLongPressKind {
  Link = 0,
  Image = 1
}

export interface WebLongPressTarget {
  kind: WebLongPressKind;
  url: string;
  title: string;
}

interface LongPressPayload {
  kind?: string;
  url?: string;
  title?: string;
}

/**
 * The narrow browser engine boundary. UI code deals in browser actions while
 * ArkWeb-specific controller calls stay in one place.
 */
export class WebKernelService {
  private static defaultUserAgent: string = '';

  static load(controller: webview.WebviewController, url: string): void {
    WebKernelService.run('load', (): void => controller.loadUrl(url));
  }

  static reload(controller: webview.WebviewController, force: boolean = false): void {
    WebKernelService.run('reload', (): void => {
      if (force) {
        controller.removeCache(true);
        controller.refresh();
      } else {
        controller.refresh();
      }
    });
  }

  static stop(controller: webview.WebviewController): void {
    WebKernelService.run('stop', (): void => controller.stop());
  }

  static goBack(controller: webview.WebviewController): void {
    WebKernelService.run('goBack', (): void => controller.backward());
  }

  static goForward(controller: webview.WebviewController): void {
    WebKernelService.run('goForward', (): void => controller.forward());
  }

  static findAll(controller: webview.WebviewController, query: string): void {
    WebKernelService.run('findAll', (): void => controller.searchAllAsync(query));
  }

  static findNext(controller: webview.WebviewController, forward: boolean): void {
    WebKernelService.run('findNext', (): void => controller.searchNext(forward));
  }

  static clearFind(controller: webview.WebviewController): void {
    WebKernelService.run('clearFind', (): void => controller.clearMatches());
  }

  static async getLongPressTarget(controller: webview.WebviewController): Promise<WebLongPressTarget | undefined> {
    try {
      const raw: string = await controller.runJavaScript('window.__mbResolveLongPressTarget ? window.__mbResolveLongPressTarget() : ""');
      let encoded: string = raw;
      try {
        const decoded: string = JSON.parse(raw) as string;
        if (typeof decoded === 'string') {
          encoded = decoded;
        }
      } catch (_error) {
        // The ArkWeb bridge can return either a JSON string or its decoded value.
      }
      if (encoded.length === 0) {
        return undefined;
      }
      const parsed: LongPressPayload = JSON.parse(encoded) as LongPressPayload;
      if (parsed.url === undefined || !/^https?:/i.test(parsed.url)) {
        return undefined;
      }
      const kind: WebLongPressKind | undefined = parsed.kind === 'image'
        ? WebLongPressKind.Image
        : parsed.kind === 'link'
          ? WebLongPressKind.Link
          : undefined;
      if (kind === undefined) {
        return undefined;
      }
      return { kind: kind, url: parsed.url, title: parsed.title ?? '' };
    } catch (error) {
      Logger.warn(TAG, `Unable to read long-press target: ${String(error)}`);
      return undefined;
    }
  }

  static goBackBySteps(controller: webview.WebviewController, step: number): void {
    if (!WebKernelService.isBackwardStep(step)) {
      return;
    }
    WebKernelService.run('goBackBySteps', (): void => controller.backOrForward(step));
  }

  /** Keeps UI state in the same range as ArkWeb's progress callback contract. */
  static clampProgress(progress: number): number {
    if (Number.isNaN(progress)) {
      return 0;
    }
    return Math.min(100, Math.max(0, progress));
  }

  /**
   * Evaluates whether the page-end completion path should run.
   * An early return is required if the same document has already completed,
   * avoiding duplicate processing caused by progress updates.
   */
  static shouldRunPageEnd(lastCompletedUrl: string | undefined, currentUrl: string): boolean {
    if (lastCompletedUrl !== undefined && isSameDocumentUrl(lastCompletedUrl, currentUrl)) {
      return false;
    }
    return true;
  }

  /** Back-history navigation is expressed as a negative relative step. */
  static isBackwardStep(step: number): boolean {
    return step < 0;
  }

  /** Subframe commits must not affect the tab-level back and forward controls. */
  static shouldRefreshNavigationState(isMainFrame: boolean): boolean {
    return isMainFrame;
  }

  /** Native home is outside ArkWeb history, but remains a valid back destination. */
  static canNavigateBack(hasWebHistory: boolean, isHome: boolean): boolean {
    return hasWebHistory || WebKernelService.shouldReturnHomeOnBack(hasWebHistory, isHome);
  }

  static shouldReturnHomeOnBack(hasWebHistory: boolean, isHome: boolean): boolean {
    return !hasWebHistory && !isHome;
  }

  static getBackHistory(controller: webview.WebviewController): WebHistoryEntry[] {
    try {
      const list: webview.BackForwardList = controller.getBackForwardEntries();
      const entries: WebHistoryEntry[] = [];
      const firstIndex: number = Math.max(0, list.currentIndex - 12);
      for (let index: number = list.currentIndex - 1; index >= firstIndex; index -= 1) {
        const item: webview.HistoryItem = list.getItemAtIndex(index);
        entries.push({
          title: item.title.length > 0 ? item.title : item.historyUrl,
          url: item.historyUrl,
          step: index - list.currentIndex
        });
      }
      return entries;
    } catch (error) {
      Logger.warn(TAG, `Unable to read back history: ${String(error)}`);
      return [];
    }
  }

  static canGoBack(controller: webview.WebviewController): boolean {
    try {
      return controller.accessBackward();
    } catch (error) {
      Logger.warn(TAG, `Unable to query backward history: ${String(error)}`);
      return false;
    }
  }

  static canGoForward(controller: webview.WebviewController): boolean {
    try {
      return controller.accessForward();
    } catch (error) {
      Logger.warn(TAG, `Unable to query forward history: ${String(error)}`);
      return false;
    }
  }

  static applyUserAgent(controller: webview.WebviewController, isDesktop: boolean): boolean {
    try {
      if (WebKernelService.defaultUserAgent.length === 0) {
        WebKernelService.defaultUserAgent = controller.getUserAgent();
      }
      const targetUa: string = WebKernelService.userAgentFor(
        isDesktop,
        WebKernelService.defaultUserAgent
      );
      let currentUa: string = '';
      try {
        currentUa = controller.getCustomUserAgent();
      } catch (_error) {
        currentUa = '';
      }
      if (currentUa === targetUa) {
        return false;
      }
      controller.setCustomUserAgent(targetUa);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Unable to apply user agent: ${String(error)}`);
      return false;
    }
  }

  private static resolveCompatibleChromeVersion(stockUserAgent: string): string {
    const match: RegExpMatchArray | null = stockUserAgent.match(/Chrome\/(\d+)\.(\d+\.\d+\.\d+)/);
    if (match !== null && Number(match[1]) >= MIN_COMPATIBLE_CHROME_MAJOR) {
      return `${match[1]}.${match[2]}`;
    }
    return `${MIN_COMPATIBLE_CHROME_MAJOR}.0.0.0`;
  }

  static resolveDesktopUserAgent(stockUserAgent: string): string {
    const version: string = WebKernelService.resolveCompatibleChromeVersion(stockUserAgent);
    return DESKTOP_USER_AGENT.replace(/Chrome\/\d+\.\d+\.\d+\.\d+/, `Chrome/${version}`);
  }

  static resolveCompatibleMobileUserAgent(stockUserAgent: string): string {
    const version: string = WebKernelService.resolveCompatibleChromeVersion(stockUserAgent);
    return COMPATIBLE_MOBILE_USER_AGENT.replace(/Chrome\/\d+\.\d+\.\d+\.\d+/, `Chrome/${version}`);
  }

  static userAgentFor(isDesktop: boolean, mobileUserAgent: string): string {
    if (isDesktop) {
      return WebKernelService.resolveDesktopUserAgent(mobileUserAgent);
    }
    return WebKernelService.resolveCompatibleMobileUserAgent(mobileUserAgent);
  }

  /** Known mobile-only entry points that cannot negotiate a desktop page from UA alone. */
  static desktopUrlFor(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^(https?):\/\/([^/?#]+)(.*)$/i);
    if (match === null || match[2].split(':')[0].toLowerCase() !== 'm.weibo.cn') {
      return url;
    }
    return `https://weibo.com${match[3]}`;
  }

  static resolveContextMenuTarget(
    linkUrl: string,
    sourceUrl: string,
    hasImage: boolean,
    selectionText: string
  ): WebLongPressTarget | undefined {
    const trimmedLink: string = linkUrl.trim();
    if (/^https?:/i.test(trimmedLink)) {
      return {
        kind: WebLongPressKind.Link,
        url: trimmedLink,
        title: selectionText.trim()
      };
    }
    const trimmedSource: string = sourceUrl.trim();
    if (hasImage && /^https?:/i.test(trimmedSource)) {
      return {
        kind: WebLongPressKind.Image,
        url: trimmedSource,
        title: selectionText.trim()
      };
    }
    return undefined;
  }

  static resolveFileSelectorMaxCount(mode: number): number {
    return mode === 1 ? 50 : 1;
  }

  static stepSiteZoomPercent(currentPercent: number, deltaPercent: number): number {
    const base: number = Number.isFinite(currentPercent) && currentPercent >= 50 && currentPercent <= 200
      ? currentPercent
      : 100;
    return Math.min(200, Math.max(50, base + deltaPercent));
  }

  static applyZoomPercent(controller: webview.WebviewController, percent: number): void {
    const clamped: number = WebKernelService.stepSiteZoomPercent(percent, 0);
    const factor: number = clamped / 100;
    WebKernelService.run('zoom', (): void => controller.zoom(factor));
  }

  static shouldShowDialog(tabId: string, activeTabId: string): boolean {
    return tabId === activeTabId;
  }
  private static run(name: string, action: () => void): void {
    try {
      action();
    } catch (error) {
      Logger.warn(TAG, `${name} failed: ${String(error)}`);
    }
  }
}
