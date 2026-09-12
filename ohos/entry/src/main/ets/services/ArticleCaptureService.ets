import { webview } from '@kit.ArkWeb';
import { ARTICLE_CAPTURE_SCRIPT } from '../constants/AppConstants';
import { ArticleCaptureSnapshot, articleCaptureReadable, parseArticleCapture } from '../models/ArticleCaptureModels';

/** Waits for a stable readable DOM, with a bounded retry window for dynamic articles. */
export class ArticleCaptureService {
  static async capture(controller: webview.WebviewController): Promise<ArticleCaptureSnapshot> {
    let previousText: string = '';
    let latest: ArticleCaptureSnapshot | undefined = undefined;
    for (let attempt: number = 0; attempt < 6; attempt++) {
      latest = parseArticleCapture(await ArticleCaptureService.readSnapshot(controller));
      if (articleCaptureReadable(latest) && latest.text === previousText) {
        return latest;
      }
      previousText = latest.text;
      if (attempt < 5) {
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 600); });
      }
    }
    if (latest === undefined) {
      throw new Error('Article capture did not return a snapshot');
    }
    if (articleCaptureReadable(latest)) {
      latest.quality = 'partial';
    }
    return latest;
  }

  private static readSnapshot(controller: webview.WebviewController): Promise<string> {
    return new Promise<string>((resolve, reject): void => {
      const timer: number = setTimeout((): void => reject(new Error('Article capture timed out')), 5000);
      try {
        controller.runJavaScript(ARTICLE_CAPTURE_SCRIPT).then((result: string): void => {
          clearTimeout(timer);
          resolve(result);
        }).catch((error: Error): void => { clearTimeout(timer); reject(error); });
      } catch (error) {
        clearTimeout(timer);
        reject(new Error('Article capture unavailable'));
      }
    });
  }
}
