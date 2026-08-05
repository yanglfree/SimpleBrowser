import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppearanceMode, cloneSettings } from '../models/BrowserModels';
import { BrowserRepository } from '../repositories/BrowserRepository';
import { ThemeService } from '../services/ThemeService';
import { AppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    AppContext.setContext(this.context);
    Logger.info(TAG, 'Ability created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        Logger.error(TAG, `Failed to load page: ${JSON.stringify(error)}`);
        return;
      }
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

  onDestroy(): void {
    Logger.info(TAG, 'Ability destroyed');
  }
}
