import { display } from '@kit.ArkUI';
import {
  BrowserFoldMetrics,
  FoldCreaseMetrics,
  emptyFoldMetrics
} from '../models/FoldMetrics';
import { Logger } from '../utils/Logger';

const TAG: string = 'FoldStateService';

export type FoldMetricsListener = (metrics: BrowserFoldMetrics) => void;

export class FoldStateService {
  private uiContext: UIContext | undefined = undefined;
  private listener: FoldMetricsListener | undefined = undefined;
  private readonly foldListener = (_status: display.FoldStatus): void => this.emit();
  private readonly displayListener = (_displayId: number): void => this.emit();

  start(uiContext: UIContext, listener: FoldMetricsListener): void {
    this.stop();
    this.uiContext = uiContext;
    this.listener = listener;
    try {
      display.on('foldStatusChange', this.foldListener);
      display.on('change', this.displayListener);
    } catch (error) {
      Logger.info(TAG, `Fold listeners unavailable: ${String(error)}`);
    }
    this.emit();
  }

  stop(): void {
    try {
      display.off('foldStatusChange', this.foldListener);
      display.off('change', this.displayListener);
    } catch (error) {
      Logger.debug(TAG, `Fold listener cleanup skipped: ${String(error)}`);
    }
    this.uiContext = undefined;
    this.listener = undefined;
  }

  private emit(): void {
    const listener: FoldMetricsListener | undefined = this.listener;
    if (listener === undefined) {
      return;
    }
    try {
      const status: display.FoldStatus = display.getFoldStatus();
      const isHalfFolded: boolean = status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
        status === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_HALF_FOLDED;
      if (!isHalfFolded) {
        listener(emptyFoldMetrics());
        return;
      }
      const region: display.FoldCreaseRegion = display.getCurrentFoldCreaseRegion();
      const rect: display.Rect | undefined = region.creaseRects[0];
      const uiContext: UIContext | undefined = this.uiContext;
      if (rect === undefined || uiContext === undefined || rect.width <= 0 || rect.height <= 0) {
        listener({ isHalfFolded: true });
        return;
      }
      const crease: FoldCreaseMetrics = {
        leftVp: uiContext.px2vp(rect.left),
        topVp: uiContext.px2vp(rect.top),
        widthVp: uiContext.px2vp(rect.width),
        heightVp: uiContext.px2vp(rect.height)
      };
      listener({ isHalfFolded: true, crease: crease });
    } catch (error) {
      Logger.debug(TAG, `Fold state unavailable: ${String(error)}`);
      listener(emptyFoldMetrics());
    }
  }
}
