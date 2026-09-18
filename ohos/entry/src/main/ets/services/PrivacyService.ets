import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from '../utils/Logger';
import {
  CookiePair,
  cookieFlushUrls,
  deviceDropsSessionCookies,
  isHttpsUrl,
  parseCookiePairs,
  persistentSetCookie
} from './CookiePersistence';

const TAG: string = 'PrivacyService';

export class PrivacyService {
  private static webEngineReady: boolean = false;
  private static pendingCookieClear: boolean = false;
  private static pendingPrivateClear: boolean = false;
  private static cookieUrls: string[] = [];

  // Only an attached Web component proves native initialization has completed.
  // Constructing a controller does not make CookieManager safe to call.
  static onWebControllerAttached(): void {
    PrivacyService.webEngineReady = true;
    try {
      webview.WebviewController.setWebDebuggingAccess(true);
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    } catch (error) {
      Logger.warn(TAG, `Failed to configure cookies or debugging: ${String(error)}`);
    }
    if (PrivacyService.pendingCookieClear) {
      PrivacyService.pendingCookieClear = false;
      PrivacyService.clearCookies();
    }
    if (PrivacyService.pendingPrivateClear) {
      PrivacyService.pendingPrivateClear = false;
      PrivacyService.clearPrivateSiteData([]);
    }
  }

  static clearCookiesWhenReady(): void {
    if (!PrivacyService.webEngineReady) {
      PrivacyService.pendingCookieClear = true;
      return;
    }
    PrivacyService.clearCookies();
  }

  static clearPrivateSiteDataWhenReady(controllers: webview.WebviewController[]): void {
    if (!PrivacyService.webEngineReady) {
      PrivacyService.pendingPrivateClear = true;
      return;
    }
    PrivacyService.clearPrivateSiteData(controllers);
  }

  static rememberCookieUrls(tabUrls: string[], historyUrls: string[]): void {
    PrivacyService.cookieUrls = cookieFlushUrls(tabUrls, historyUrls, 24);
  }

  /**
   * ArkWeb writes cookies to disk every ~30s; a session cookie set by a login
   * can be lost when a tab closes or the process dies before the next flush.
   * saveCookieSync() forces the write synchronously so logins survive tab close
   * and relaunch — the async cousin can race with engine shutdown.
   */
  static flushCookies(): void {
    // A cold homepage has no new cookies to persist. Never initialize ArkWeb
    // from lifecycle cleanup: native initialization failures bypass try/catch.
    if (!PrivacyService.webEngineReady) {
      return;
    }
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
      Logger.warn(TAG, `Failed to flush cookies: ${String(error)}`);
    }
  }

  /**
   * Tablet/2-in-1/PC kernels skip session cookies in saveCookieSync. Promote
   * those cookies to Max-Age before the flush so a force-stop keeps the login.
   * Call only when the process may die — rewriting on every page-end would
   * strip Domain/SameSite from live OAuth cookies.
   */
  static persistCookiesAcrossProcessDeath(): void {
    if (!PrivacyService.webEngineReady) {
      return;
    }
    if (deviceDropsSessionCookies(PrivacyService.deviceType())) {
      PrivacyService.promoteSessionCookies();
    }
    PrivacyService.flushCookies();
  }

  private static deviceType(): string {
    try {
      return deviceInfo.deviceType;
    } catch (_error) {
      return 'tablet';
    }
  }

  private static promoteSessionCookies(): void {
    const urls: string[] = PrivacyService.cookieUrls;
    for (let index: number = 0; index < urls.length; index += 1) {
      const url: string = urls[index];
      let header: string = '';
      try {
        header = webview.WebCookieManager.fetchCookieSync(url);
      } catch (_error) {
        continue;
      }
      const pairs: CookiePair[] = parseCookiePairs(header);
      const https: boolean = isHttpsUrl(url);
      for (let pairIndex: number = 0; pairIndex < pairs.length; pairIndex += 1) {
        const pair: CookiePair = pairs[pairIndex];
        try {
          webview.WebCookieManager.configCookieSync(
            url,
            persistentSetCookie(pair.name, pair.value, https),
            false,
            true
          );
        } catch (error) {
          Logger.warn(TAG, `Failed to persist session cookie ${pair.name}: ${String(error)}`);
        }
      }
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
