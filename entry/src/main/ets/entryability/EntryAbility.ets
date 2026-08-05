import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
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
      this.applySystemBarStyle(windowStage);
      Logger.info(TAG, 'Browser page loaded');
    });
  }

  private applySystemBarStyle(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      const properties: window.SystemBarProperties = {
        statusBarColor: '#0D1117',
        navigationBarColor: '#0D1117',
        statusBarContentColor: '#F0F6FC',
        navigationBarContentColor: '#F0F6FC',
        isStatusBarLightIcon: false,
        isNavigationBarLightIcon: false
      };
      mainWindow.setWindowBackgroundColor('#0D1117');
      mainWindow.setWindowSystemBarProperties(properties).catch((error: Error): void => {
        Logger.warn(TAG, `Failed to apply system bar style: ${String(error)}`);
      });
    } catch (error) {
      Logger.warn(TAG, `Failed to configure system bars: ${String(error)}`);
    }
  }

  onWindowStageDestroy(): void {
    Logger.info(TAG, 'Window stage destroyed');
  }

  onDestroy(): void {
    Logger.info(TAG, 'Ability destroyed');
  }
}
