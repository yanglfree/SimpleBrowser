import { webview } from '@kit.ArkWeb';
import environment from '@ohos.file.environment';
import { Logger } from '../utils/Logger';

const TAG: string = 'DownloadService';

export class DownloadService {
  private static isConfigured: boolean = false;

  static configure(): void {
    if (DownloadService.isConfigured) {
      return;
    }
    const delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => DownloadService.start(item));
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      Logger.info(TAG, `Download finished: ${item.getSuggestedFileName()}`);
    });
    delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      Logger.warn(TAG, `Download failed: ${item.getSuggestedFileName()}`);
    });
    webview.WebDownloadManager.setDownloadDelegate(delegate);
    DownloadService.isConfigured = true;
  }

  private static start(item: webview.WebDownloadItem): void {
    try {
      const safeName: string = DownloadService.safeFileName(item.getSuggestedFileName());
      const targetPath: string = `${environment.getUserDownloadDir()}/${safeName}`;
      item.start(targetPath);
      Logger.info(TAG, `Download started: ${safeName}`);
    } catch (error) {
      Logger.error(TAG, `Failed to start download: ${String(error)}`);
      item.cancel();
    }
  }

  private static safeFileName(value: string): string {
    const normalized: string = value.replace(/[\\/:*?"<>|]/g, '_').trim();
    return normalized.length > 0 ? normalized : `download-${Date.now()}`;
  }
}
