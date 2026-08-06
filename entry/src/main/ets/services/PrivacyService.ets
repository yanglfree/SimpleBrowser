import { webview } from '@kit.ArkWeb';
import { Logger } from '../utils/Logger';

const TAG: string = 'PrivacyService';

export class PrivacyService {
  /** Backs "关闭标签时清除 Cookie" and the private-tab teardown. */
  static clearCookies(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (error) {
      Logger.warn(TAG, `Failed to clear cookies: ${String(error)}`);
    }
  }

  /** Clears cookies and Web Storage. Bookmarks are deliberately untouched. */
  static clearCookiesAndStorage(): void {
    PrivacyService.clearCookies();
    try {
      webview.WebStorage.deleteAllData();
    } catch (error) {
      Logger.warn(TAG, `Failed to clear web storage: ${String(error)}`);
    }
  }

  /** Clears HTTP cache for the currently mounted web views. */
  static clearCache(controllers: webview.WebviewController[]): void {
    for (const controller of controllers) {
      try {
        controller.removeCache(true);
      } catch (error) {
        Logger.warn(TAG, `Failed to clear cache: ${String(error)}`);
      }
    }
  }

  /** Backs the legacy one-tap clear-all flow. */
  static clearSiteData(controllers: webview.WebviewController[]): void {
    PrivacyService.clearCookiesAndStorage();
    PrivacyService.clearCache(controllers);
  }
}
