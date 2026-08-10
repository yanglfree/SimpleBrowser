import { webview } from '@kit.ArkWeb';
import { Logger } from '../utils/Logger';

const TAG: string = 'PrivacyService';

export class PrivacyService {
  /**
   * ArkWeb writes cookies to disk every ~30s; a session cookie set by a login
   * can be lost when a tab closes or the process dies before the next flush.
   * saveCookieSync() forces the write synchronously so logins survive tab close
   * and relaunch — the async cousin can race with engine shutdown.
   */
  static flushCookies(): void {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
      Logger.warn(TAG, `Failed to flush cookies: ${String(error)}`);
    }
  }

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

  /** Clears the isolated cookie, storage, and cache stores used by private tabs. */
  static clearPrivateSiteData(controllers: webview.WebviewController[]): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (error) {
      Logger.warn(TAG, `Failed to clear private cookies: ${String(error)}`);
    }
    try {
      webview.WebStorage.deleteAllData(true);
    } catch (error) {
      Logger.warn(TAG, `Failed to clear private web storage: ${String(error)}`);
    }
    PrivacyService.clearCache(controllers);
  }
}
