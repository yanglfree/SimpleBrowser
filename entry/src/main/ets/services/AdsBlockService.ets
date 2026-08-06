import { common } from '@kit.AbilityKit';
import { connection, http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';
import { CosmeticFilterService } from './CosmeticFilterService';
import { RuleCache, RuleEngine, RuleMatchContext } from './RuleEngine';

const TAG: string = 'AdsBlockService';
const RULE_FILE_NAME: string = 'minimal-browser-easylist.txt';
const RULE_CACHE_FILE_NAME: string = 'minimal-browser-easylist.cache.json';
const RULE_UPDATED_FILE_NAME: string = 'minimal-browser-easylist.updated-at';
const RULE_UPDATE_URL: string = 'https://easylist.to/easylist/easylist.txt';
const RULE_UPDATE_INTERVAL_MS: number = 3 * 24 * 60 * 60 * 1000;

export class AdsBlockService {
  private static compiledEngine: RuleEngine | undefined;
  private static cosmeticFilter: CosmeticFilterService | undefined;
  private rulesPath: string = '';
  private cachePath: string = '';
  private updatedAtPath: string = '';
  private ruleEngine: RuleEngine | undefined;
  private isInitialized: boolean = false;
  private updating: boolean = false;
  private updatedAt: number = 0;

  async initialize(context: common.UIAbilityContext): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    try {
      this.rulesPath = `${context.filesDir}/${RULE_FILE_NAME}`;
      this.cachePath = `${context.filesDir}/${RULE_CACHE_FILE_NAME}`;
      this.updatedAtPath = `${context.filesDir}/${RULE_UPDATED_FILE_NAME}`;
      const content: Uint8Array = context.resourceManager.getRawFileContentSync('ads/easylist.txt');
      const bundledRulesText: string = new util.TextDecoder().decodeToString(content);
      const rulesText: string = this.readPersistedRules(bundledRulesText);
      this.updatedAt = this.readUpdatedAt();
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
      fs.writeSync(file.fd, rulesText);
      fs.closeSync(file.fd);
      webview.AdsBlockManager.setAdsBlockRules(this.rulesPath, true);
      this.isInitialized = true;
      Logger.info(TAG, 'Ads block rules loaded');
      void this.updateRulesIfNeeded();
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

  get lastUpdatedAt(): number {
    return this.updatedAt;
  }

  async updateRulesIfNeeded(): Promise<boolean> {
    if (this.updatedAt > 0 && Date.now() - this.updatedAt < RULE_UPDATE_INTERVAL_MS) {
      return false;
    }
    if (!this.isWifiConnected()) {
      return false;
    }
    return await this.updateRules(true);
  }

  async updateRules(force: boolean = false): Promise<boolean> {
    if (!this.isInitialized || this.updating) {
      return false;
    }
    if (!force && this.updatedAt > 0 && Date.now() - this.updatedAt < RULE_UPDATE_INTERVAL_MS) {
      return false;
    }
    this.updating = true;
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(RULE_UPDATE_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 30000,
        header: { 'accept': 'text/plain' }
      });
      if (Number(response.responseCode) < 200 || Number(response.responseCode) >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const rulesText: string = typeof response.result === 'string'
        ? response.result
        : new util.TextDecoder().decodeToString(new Uint8Array(response.result as ArrayBuffer));
      const engine: RuleEngine = RuleEngine.compile(rulesText);
      if (rulesText.trim().length === 0 || engine.ruleCount === 0) {
        throw new Error('Remote rules are empty');
      }
      this.writeRulesAtomically(rulesText);
      const fingerprint: number = RuleEngine.fingerprint(rulesText);
      this.ruleEngine = engine;
      AdsBlockService.compiledEngine = engine;
      AdsBlockService.cosmeticFilter = CosmeticFilterService.compile(rulesText);
      this.saveCompiledCache(engine.serialize(fingerprint));
      webview.AdsBlockManager.setAdsBlockRules(this.rulesPath, true);
      this.updatedAt = Date.now();
      this.saveUpdatedAt(this.updatedAt);
      Logger.info(TAG, `Updated ${engine.ruleCount} ad rules`);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Failed to update ad rules; keeping the current list: ${String(error)}`);
      return false;
    } finally {
      request.destroy();
      this.updating = false;
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

  private readPersistedRules(fallback: string): string {
    try {
      if (!fs.accessSync(this.rulesPath)) {
        return fallback;
      }
      const persisted: string = fs.readTextSync(this.rulesPath);
      return persisted.trim().length > 0 ? persisted : fallback;
    } catch (_error) {
      return fallback;
    }
  }

  private readUpdatedAt(): number {
    try {
      if (!fs.accessSync(this.updatedAtPath)) {
        return 0;
      }
      const value: number = Number(fs.readTextSync(this.updatedAtPath));
      return Number.isFinite(value) && value > 0 ? value : 0;
    } catch (_error) {
      return 0;
    }
  }

  private saveUpdatedAt(value: number): void {
    try {
      const file: fs.File = fs.openSync(
        this.updatedAtPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, `${value}`);
      fs.closeSync(file.fd);
    } catch (error) {
      Logger.warn(TAG, `Failed to save ad rules update time: ${String(error)}`);
    }
  }

  private writeRulesAtomically(rulesText: string): void {
    const temporaryPath: string = `${this.rulesPath}.next`;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, rulesText);
      } finally {
        fs.closeSync(file.fd);
      }
      fs.renameSync(temporaryPath, this.rulesPath);
    } catch (error) {
      try {
        if (fs.accessSync(temporaryPath)) {
          fs.unlinkSync(temporaryPath);
        }
      } catch (_cleanupError) {
        // Best-effort cleanup; the current rules remain in place.
      }
      throw new Error(String(error));
    }
  }

  private isWifiConnected(): boolean {
    try {
      const netHandle: connection.NetHandle = connection.getDefaultNetSync();
      const capabilities: connection.NetCapabilities = connection.getNetCapabilitiesSync(netHandle);
      return capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    } catch (error) {
      Logger.warn(TAG, `Unable to determine network type: ${String(error)}`);
      return false;
    }
  }
}
