import { common, Want } from '@kit.AbilityKit';
import StartOptions from '@ohos.app.ability.StartOptions';
import { window } from '@kit.ArkUI';
import { BrowserTab, cloneTab } from '../models/BrowserModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'MultiWindowService';
const BUNDLE_NAME: string = 'com.youdroid.dolphin';

export class MultiWindowService {
  static async isSupported(): Promise<boolean> {
    try {
      await window.getGlobalWindowMode();
      return true;
    } catch (error) {
      Logger.info(TAG, `Multi-window is unavailable: ${String(error)}`);
      return false;
    }
  }

  static async moveTab(context: common.UIAbilityContext, tab: BrowserTab): Promise<boolean> {
    const token: string = `window-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: 'EntryAbility',
      parameters: {
        'dolphin.windowToken': token,
        'dolphin.tabTransfer': JSON.stringify(cloneTab(tab))
      }
    };
    const options: StartOptions = {
      withAnimation: true,
      windowWidth: 1100,
      windowHeight: 760
    };
    try {
      await context.startAbility(want, options);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Failed to move tab to a new window: ${String(error)}`);
      return false;
    }
  }
}
