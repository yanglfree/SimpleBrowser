import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';
import { CosmeticFilterService } from './CosmeticFilterService';
import { RuleCache, RuleEngine, RuleMatchContext } from './RuleEngine';

const TAG: string = 'AdsBlockService';
const RULE_FILE_NAME: string = 'minimal-browser-easylist.txt';
const RULE_CACHE_FILE_NAME: string = 'minimal-browser-easylist.cache.json';

export class AdsBlockService {
  private static compiledEngine: RuleEngine | undefined;
  private static cosmeticFilter: CosmeticFilterService | undefined;
  private rulesPath: string = '';
  private cachePath: string = '';
  private ruleEngine: RuleEngine | undefined;
  private isInitialized: boolean = false;

  async initialize(context: common.UIAbilityContext): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    try {
      this.rulesPath = `${context.filesDir}/${RULE_FILE_NAME}`;
      this.cachePath = `${context.filesDir}/${RULE_CACHE_FILE_NAME}`;
      const content: Uint8Array = context.resourceManager.getRawFileContentSync('ads/easylist.txt');
      const rulesText: string = new util.TextDecoder().decodeToString(content);
      AdsBlockService.cosmeticFilter = CosmeticFilterService.compile(rulesText);
      const fingerprint: number = RuleEngine.fingerprint(rulesText);
      const cachedEngine: RuleEngine | undefined = this.loadCompiledCache(fingerprint);
      const engine: RuleEngine = cachedEngine ?? RuleEngine.compile(rulesText);
      this.ruleEngine = engine;
      AdsBlockService.compiledEngine = engine;
      if (cachedEngine === undefined) {
        this.saveCompiledCache(engine.serialize(fingerprint));
        Logger.info(TAG, `Compiled ${engine.ruleCount} ad rules`);
      } else {
        Logger.info(TAG, `Loaded ${engine.ruleCount} cached ad rules`);
      }
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

  shouldBlock(context: RuleMatchContext): boolean {
    const engine: RuleEngine | undefined = this.ruleEngine ?? AdsBlockService.compiledEngine;
    return engine?.shouldBlock(context) ?? false;
  }

  static cosmeticScriptFor(pageUrl: string): string {
    return AdsBlockService.cosmeticFilter?.scriptFor(pageUrl) ?? '';
  }

  interceptRequest(
    request: WebResourceRequest,
    pageUrl: string,
    enabled: boolean
  ): WebResourceResponse | null {
    if (!enabled || !this.shouldBlock({ url: request.getRequestUrl(), pageUrl: pageUrl })) {
      return null;
    }
    try {
      const response: WebResourceResponse = new WebResourceResponse();
      response.setResponseData('');
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType('text/plain');
      response.setReasonMessage('Blocked by browser rule');
      response.setResponseCode(204);
      response.setResponseIsReady(true);
      return response;
    } catch (error) {
      Logger.warn(TAG, `Failed to build blocked response: ${String(error)}`);
      return null;
    }
  }

  get ruleCount(): number {
    return this.ruleEngine?.ruleCount ?? 0;
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

  private loadCompiledCache(fingerprint: number): RuleEngine | undefined {
    if (this.cachePath.length === 0) {
      return undefined;
    }
    try {
      const cache: RuleCache = JSON.parse(fs.readTextSync(this.cachePath)) as RuleCache;
      if (cache.fingerprint !== fingerprint) {
        return undefined;
      }
      return RuleEngine.fromCache(cache);
    } catch (_error) {
      return undefined;
    }
  }

  private saveCompiledCache(cache: RuleCache): void {
    try {
      const file: fs.File = fs.openSync(
        this.cachePath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, JSON.stringify(cache));
      fs.closeSync(file.fd);
    } catch (error) {
      Logger.warn(TAG, `Failed to save compiled ad rules: ${String(error)}`);
    }
  }
}
