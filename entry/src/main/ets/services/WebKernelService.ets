import { webview } from '@kit.ArkWeb';
import { DESKTOP_USER_AGENT } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

const TAG: string = 'WebKernelService';

export interface WebKernelCallbacks {
  onPageBegin: (url: string) => void;
  onProgressChange: (progress: number) => void;
  onPageEnd: (url: string) => void;
  onError: (code: number, message: string) => void;
}

export interface WebHistoryEntry {
  title: string;
  url: string;
  step: number;
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

  /** Back-history navigation is expressed as a negative relative step. */
  static isBackwardStep(step: number): boolean {
    return step < 0;
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

  static applyUserAgent(controller: webview.WebviewController, isDesktop: boolean): void {
    try {
      if (WebKernelService.defaultUserAgent.length === 0) {
        WebKernelService.defaultUserAgent = controller.getUserAgent();
      }
      controller.setCustomUserAgent(WebKernelService.userAgentFor(
        isDesktop,
        WebKernelService.defaultUserAgent
      ));
    } catch (error) {
      Logger.warn(TAG, `Unable to apply user agent: ${String(error)}`);
    }
  }

  static userAgentFor(isDesktop: boolean, mobileUserAgent: string): string {
    return isDesktop ? DESKTOP_USER_AGENT : mobileUserAgent;
  }

  private static run(name: string, action: () => void): void {
    try {
      action();
    } catch (error) {
      Logger.warn(TAG, `${name} failed: ${String(error)}`);
    }
  }
}
