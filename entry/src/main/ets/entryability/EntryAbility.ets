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
      Logger.info(TAG, 'Browser page loaded');
    });
  }

  onWindowStageDestroy(): void {
    Logger.info(TAG, 'Window stage destroyed');
  }

  onDestroy(): void {
    Logger.info(TAG, 'Ability destroyed');
  }
}
