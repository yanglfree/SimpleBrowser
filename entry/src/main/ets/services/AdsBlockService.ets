import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';

const TAG: string = 'AdsBlockService';
const RULE_FILE_NAME: string = 'minimal-browser-easylist.txt';

export class AdsBlockService {
  private rulesPath: string = '';
  private isInitialized: boolean = false;

  async initialize(context: common.UIAbilityContext): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    try {
      this.rulesPath = `${context.filesDir}/${RULE_FILE_NAME}`;
      const content: Uint8Array = context.resourceManager.getRawFileContentSync('ads/easylist.txt');
      const file: fs.File = fs.openSync(
        this.rulesPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, content.buffer as ArrayBuffer);
      fs.closeSync(file.fd);
      webview.AdsBlockManager.setAdsBlockRules(this.rulesPath, true);
      this.isInitialized = true;
      Logger.info(TAG, 'Ads block rules loaded');
      return true;
    } catch (error) {
      Logger.error(TAG, `Failed to load ad rules: ${String(error)}`);
      return false;
    }
  }

  configure(controller: webview.WebviewController, enabled: boolean): void {
    try {
      controller.enableAdsBlock(enabled);
    } catch (error) {
      Logger.error(TAG, `Failed to configure controller: ${String(error)}`);
    }
  }

  /** Hosts the user turned blocking off for, from the blocking panel. */
  applyAllowedHosts(hosts: string[]): void {
    try {
      webview.AdsBlockManager.clearAdsBlockAllowedList();
      if (hosts.length > 0) {
        webview.AdsBlockManager.addAdsBlockAllowedList(hosts);
      }
    } catch (error) {
      Logger.error(TAG, `Failed to apply allowed hosts: ${String(error)}`);
    }
  }
}
