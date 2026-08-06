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
      controller.setCustomUserAgent(
        isDesktop ? DESKTOP_USER_AGENT : WebKernelService.defaultUserAgent
      );
    } catch (error) {
      Logger.warn(TAG, `Unable to apply user agent: ${String(error)}`);
    }
  }

  private static run(name: string, action: () => void): void {
    try {
      action();
    } catch (error) {
      Logger.warn(TAG, `${name} failed: ${String(error)}`);
    }
  }
}
