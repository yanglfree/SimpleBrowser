import { webview } from '@kit.ArkWeb';
import { Logger } from '../utils/Logger';
import { LEGACY_HUAWEI_HOST_COOKIES, legacyHuaweiCookieDeletion } from './CookiePersistence';

const TAG: string = 'PrivacyService';

export class PrivacyService {
  private static webEngineReady: boolean = false;
  private static pendingCookieClear: boolean = false;
  private static pendingPrivateClear: boolean = false;
  private static legacyCookiesRepaired: boolean = false;

  // Only an attached Web component proves native initialization has completed.
  // Constructing a controller does not make CookieManager safe to call.
  static onWebControllerAttached(): void {
    PrivacyService.webEngineReady = true;
    try {
      webview.WebviewController.setWebDebuggingAccess(true);
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      PrivacyService.repairLegacyHuaweiCookies();
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

  /**
   * Flush the native cookie store before tab close or engine shutdown.
   * Session-cookie retention remains platform-owned; tablet kernels may omit
   * session cookies from disk. Never change expiry or scope to work around it.
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
   * A Cookie request header has no Domain, Path, HttpOnly, SameSite or expiry.
   * Recreating cookies from it shadows fresh OAuth cookies and can expose
   * HttpOnly values to scripts. Let ArkWeb retain the original attributes.
   */
  static persistCookiesAcrossProcessDeath(): void {
    PrivacyService.flushCookies();
  }

  private static repairLegacyHuaweiCookies(): void {
    if (PrivacyService.legacyCookiesRepaired) {
      return;
    }
    // Huawei's login library owns domain cookies. Older builds manufactured
    // host-only copies at Path=/; expire only those copies, never Domain cookies
    // or private-session data. Run before the first document, not on every tab.
    for (const name of LEGACY_HUAWEI_HOST_COOKIES) {
      webview.WebCookieManager.configCookieSync(
        'https://developer.huawei.com/', legacyHuaweiCookieDeletion(name), false, true
      );
    }
    webview.WebCookieManager.saveCookieSync();
    PrivacyService.legacyCookiesRepaired = true;
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
