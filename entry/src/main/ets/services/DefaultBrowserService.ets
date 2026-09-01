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

    // 1. Try navigating to "Apps & Services" settings page (application_and_service_settings)
    // where "Default apps" (默认应用) is directly located.
    try {
      const appAndServiceWant: Want = {
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_MAIN_ABILITY,
        uri: 'application_and_service_settings'
      };
      await context.startAbility(appAndServiceWant);
      Logger.info(TAG, 'Launched application_and_service_settings');
      return true;
    } catch (appAndServiceError) {
      Logger.warn(TAG, `Failed to open application_and_service_settings: ${String(appAndServiceError)}`);
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
