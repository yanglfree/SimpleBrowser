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
}
