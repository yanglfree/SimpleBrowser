import { common, Want } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'DefaultBrowserService';
const SETTINGS_BUNDLE_NAME: string = 'com.huawei.hmos.settings';
const SETTINGS_MAIN_ABILITY: string = 'com.huawei.hmos.settings.MainAbility';

export class DefaultBrowserService {
  /**
   * Guides the user to the system settings page where they can choose
   * the default browser application.
   */
  static async requestSetDefaultBrowser(context: common.UIAbilityContext): Promise<boolean> {
    const bundleName: string = context.abilityInfo?.bundleName ?? 'com.youdroid.zhuobrowser';

    // 1. Try navigating directly to Default Apps setting
    try {
      const defaultAppWant: Want = {
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_MAIN_ABILITY,
        uri: 'default_app_settings'
      };
      await context.startAbility(defaultAppWant);
      Logger.info(TAG, 'Launched default app settings');
      return true;
    } catch (defaultError) {
      Logger.warn(TAG, `Failed to open default_app_settings: ${String(defaultError)}`);
    }

    // 2. Try navigating to Application Info setting
    try {
      const appInfoWant: Want = {
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_MAIN_ABILITY,
        uri: 'application_info_entry',
        parameters: {
          pushParams: bundleName
        }
      };
      await context.startAbility(appInfoWant);
      Logger.info(TAG, 'Launched application info settings');
      return true;
    } catch (appInfoError) {
      Logger.warn(TAG, `Failed to open application_info_entry: ${String(appInfoError)}`);
    }

    // 3. Fallback to main Settings
    try {
      const generalWant: Want = {
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_MAIN_ABILITY
      };
      await context.startAbility(generalWant);
      Logger.info(TAG, 'Launched main settings');
      return true;
    } catch (generalError) {
      Logger.error(TAG, `Failed to open general settings: ${String(generalError)}`);
      return false;
    }
  }
}
