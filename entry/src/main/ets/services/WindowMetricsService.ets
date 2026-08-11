import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  BrowserWindowMetrics,
  BrowserWindowMode,
  createWindowMetrics
} from '../models/WindowMetrics';
import { Logger } from '../utils/Logger';

const TAG: string = 'WindowMetricsService';

export type WindowMetricsListener = (metrics: BrowserWindowMetrics) => void;

export class WindowMetricsService {
  private mainWindow: window.Window | undefined = undefined;
  private uiContext: UIContext | undefined = undefined;
  private listener: WindowMetricsListener | undefined = undefined;
  private widthVp: number = 0;
  private heightVp: number = 0;
  private windowMode: BrowserWindowMode = BrowserWindowMode.Unknown;
  private readonly sizeChangeListener = (size: window.Size): void => {
    this.updateSize(this.toVp(size.width), this.toVp(size.height));
  };
  private readonly statusChangeListener = (status: window.WindowStatusType): void => {
    this.windowMode = this.modeForStatus(status);
    this.emit();
  };

  async start(
    context: common.UIAbilityContext,
    uiContext: UIContext,
    listener: WindowMetricsListener
  ): Promise<BrowserWindowMetrics> {
    this.stop();
    this.uiContext = uiContext;
    this.listener = listener;
    try {
      this.mainWindow = await window.getLastWindow(context);
    } catch (error) {
      Logger.warn(TAG, `Main window is unavailable: ${String(error)}`);
      const metrics: BrowserWindowMetrics = this.currentMetrics();
      this.listener(metrics);
      return metrics;
    }
    this.readInitialState(this.mainWindow);
    try {
      this.mainWindow.on('windowSizeChange', this.sizeChangeListener);
      this.mainWindow.on('windowStatusChange', this.statusChangeListener);
    } catch (error) {
      Logger.warn(TAG, `Window status listener is unavailable: ${String(error)}`);
    }
    const metrics: BrowserWindowMetrics = this.currentMetrics();
    this.listener(metrics);
    return metrics;
  }

  stop(): void {
    if (this.mainWindow !== undefined) {
      try {
        this.mainWindow.off('windowSizeChange', this.sizeChangeListener);
        this.mainWindow.off('windowStatusChange', this.statusChangeListener);
      } catch (error) {
        Logger.warn(TAG, `Failed to unregister window listeners: ${String(error)}`);
      }
    }
    this.mainWindow = undefined;
    this.uiContext = undefined;
    this.listener = undefined;
  }

  private readInitialState(mainWindow: window.Window): void {
    let properties: window.WindowProperties;
    try {
      properties = mainWindow.getWindowProperties();
    } catch (error) {
      Logger.warn(TAG, `Window properties are unavailable: ${String(error)}`);
      return;
    }
    const drawableWidth: number = properties.drawableRect.width > 0
      ? properties.drawableRect.width
      : properties.windowRect.width;
    const drawableHeight: number = properties.drawableRect.height > 0
      ? properties.drawableRect.height
      : properties.windowRect.height;
    this.widthVp = this.toVp(drawableWidth);
    this.heightVp = this.toVp(drawableHeight);
    try {
      this.windowMode = this.modeForStatus(mainWindow.getWindowStatus());
    } catch (error) {
      this.windowMode = properties.isFullScreen ? BrowserWindowMode.FullScreen : BrowserWindowMode.Unknown;
      Logger.warn(TAG, `Window status is unavailable: ${String(error)}`);
    }
  }

  private updateSize(widthVp: number, heightVp: number): void {
    if (widthVp === this.widthVp && heightVp === this.heightVp) {
      return;
    }
    this.widthVp = widthVp;
    this.heightVp = heightVp;
    this.emit();
  }

  private emit(): void {
    if (this.listener !== undefined) {
      this.listener(this.currentMetrics());
    }
  }

  private currentMetrics(): BrowserWindowMetrics {
    return createWindowMetrics(this.widthVp, this.heightVp, this.windowMode);
  }

  private toVp(value: number): number {
    return this.uiContext?.px2vp(value) ?? 0;
  }

  private modeForStatus(status: window.WindowStatusType): BrowserWindowMode {
    switch (status) {
      case window.WindowStatusType.FULL_SCREEN:
        return BrowserWindowMode.FullScreen;
      case window.WindowStatusType.MAXIMIZE:
        return BrowserWindowMode.Maximized;
      case window.WindowStatusType.MINIMIZE:
        return BrowserWindowMode.Minimized;
      case window.WindowStatusType.FLOATING:
        return BrowserWindowMode.Floating;
      case window.WindowStatusType.SPLIT_SCREEN:
        return BrowserWindowMode.Split;
      case window.WindowStatusType.UNDEFINED:
      default:
        return BrowserWindowMode.Unknown;
    }
  }
}
