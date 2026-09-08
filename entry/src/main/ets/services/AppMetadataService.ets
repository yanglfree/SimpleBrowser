import { bundleManager } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'AppMetadataService';

export class AppMetadataService {
  static getVersionName(): string {
    try {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return bundleInfo.versionName;
    } catch (error) {
      Logger.warn(TAG, `Failed to read app version: ${String(error)}`);
      return '';
    }
  }

  static getPackageName(): string {
    try {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return bundleInfo.name;
    } catch (error) {
      Logger.warn(TAG, `Failed to read package name: ${String(error)}`);
      return 'com.youdroid.browser';
    }
  }

  static getVersionCode(): number {
    try {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return bundleInfo.versionCode;
    } catch (error) {
      Logger.warn(TAG, `Failed to read version code: ${String(error)}`);
      return 0;
    }
  }
}
