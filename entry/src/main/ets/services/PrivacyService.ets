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

  /** Backs 设置 › 隐私 › 清除浏览数据. Bookmarks are deliberately untouched. */
  static clearSiteData(controllers: webview.WebviewController[]): void {
    PrivacyService.clearCookies();
    try {
      webview.WebStorage.deleteAllData();
    } catch (error) {
      Logger.warn(TAG, `Failed to clear web storage: ${String(error)}`);
    }
    for (const controller of controllers) {
      try {
        controller.removeCache(true);
      } catch (error) {
        Logger.warn(TAG, `Failed to clear cache: ${String(error)}`);
      }
    }
  }
}
