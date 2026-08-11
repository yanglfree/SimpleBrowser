import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppearanceMode, cloneSettings } from '../models/BrowserModels';
import { BrowserRepository } from '../repositories/BrowserRepository';
import { ThemeService } from '../services/ThemeService';
import { AppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { MemoryPressureService } from '../services/MemoryPressureService';
import { TelemetryService } from '../services/TelemetryService';

const TAG: string = 'EntryAbility';

class WindowLaunchStorage {
  windowToken: string;
  windowTabTransfer: string;

  constructor(windowToken: string, windowTabTransfer: string) {
    this.windowToken = windowToken;
    this.windowTabTransfer = windowTabTransfer;
  }
}

export default class EntryAbility extends UIAbility {
  private createdAt: number = Date.now();
  private windowToken: string = '';
  private tabTransfer: string = '';

  onCreate(want: Want): void {
    const requestedToken: string = String(want.parameters?.['dolphin.windowToken'] ?? '');
    this.windowToken = requestedToken.length > 0
      ? requestedToken
      : `window-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    this.tabTransfer = String(want.parameters?.['dolphin.tabTransfer'] ?? '');
    AppContext.setContext(this.windowToken, this.context);
    TelemetryService.registerCrashObservers();
    Logger.info(TAG, 'Ability created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const storage: LocalStorage = new LocalStorage(
      new WindowLaunchStorage(this.windowToken, this.tabTransfer)
    );
    windowStage.loadContent('pages/Index', storage, (error) => {
      if (error.code) {
        Logger.error(TAG, `Failed to load page: ${JSON.stringify(error)}`);
        return;
      }
      TelemetryService.recordStartup(Date.now() - this.createdAt);
      this.applyStoredAppearance();
      Logger.info(TAG, 'Browser page loaded');
    });
  }

  /**
   * The window exists before the page reads preferences, so the saved
   * appearance is applied here too — otherwise a dark-mode user gets one frame
   * of light system bars at launch.
   */
  private applyStoredAppearance(): void {
    const repository: BrowserRepository = new BrowserRepository();
    repository.initialize(this.context).then((): void => {
      const appearance: AppearanceMode = cloneSettings(repository.getSettings()).appearance;
      ThemeService.apply(this.context, appearance);
    }).catch((error: Error): void => {
      Logger.warn(TAG, `Failed to restore appearance: ${String(error)}`);
    });
  }

  onWindowStageDestroy(): void {
    Logger.info(TAG, 'Window stage destroyed');
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    MemoryPressureService.notify(level as number);
    TelemetryService.recordMemoryPressure(level as number);
  }

  onDestroy(): void {
    AppContext.removeContext(this.windowToken);
    Logger.info(TAG, 'Ability destroyed');
  }
}
