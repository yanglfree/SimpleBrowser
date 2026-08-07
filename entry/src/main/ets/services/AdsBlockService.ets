import { common } from '@kit.AbilityKit';
import { connection, http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';
import { CosmeticFilterService } from './CosmeticFilterService';
import { RuleEngine, RuleMatchContext } from './RuleEngine';

const TAG: string = 'AdsBlockService';
const RULE_FILE_NAME: string = 'minimal-browser-easylist.txt';
const RULE_UPDATED_FILE_NAME: string = 'minimal-browser-easylist.updated-at';
const RULE_UPDATE_INTERVAL_MS: number = 3 * 24 * 60 * 60 * 1000;

interface RuleSource {
  /** Snapshot shipped in the HAP, used until the first successful update. */
  rawfile: string;
  url: string;
}

/**
 * The subscriptions the browser blocks with. EasyList alone barely covers the
 * Chinese sites on the start page, so EasyList China rides along with it; the
 * two are concatenated into the single file ArkWeb's native blocker reads.
 */
const RULE_SOURCES: RuleSource[] = [
  {
    rawfile: 'ads/easylist.txt',
    url: 'https://easylist-downloads.adblockplus.org/easylist.txt'
  },
  {
    rawfile: 'ads/easylistchina.txt',
    url: 'https://easylist-downloads.adblockplus.org/easylistchina.txt'
  }
];

export class AdsBlockService {
  private static compiledEngine: RuleEngine | undefined;
  private static cosmeticFilter: CosmeticFilterService | undefined;
  private rulesPath: string = '';
  private updatedAtPath: string = '';
  private ruleEngine: RuleEngine | undefined;
  private isInitialized: boolean = false;
  private updating: boolean = false;
  private updatedAt: number = 0;

  /**
   * Arms ArkWeb's native blocker and returns. Parsing the subscription into our
   * own engine costs a few hundred milliseconds on a full EasyList and only
   * feeds request interception and element hiding — neither of which can be
   * needed before the first page loads — so it happens after this resolves
   * rather than in front of the first frame.
   */
  async initialize(context: common.UIAbilityContext): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    try {
      this.rulesPath = `${context.filesDir}/${RULE_FILE_NAME}`;
      this.updatedAtPath = `${context.filesDir}/${RULE_UPDATED_FILE_NAME}`;
      const rulesText: string = await this.readPersistedRules(
        await AdsBlockService.readBundledRules(context)
      );
      this.updatedAt = await this.readUpdatedAt();
      await this.writeRulesAtomically(rulesText);
      webview.AdsBlockManager.setAdsBlockRules(this.rulesPath, true);
      this.isInitialized = true;
      Logger.info(TAG, 'Ads block rules loaded');
      this.compileWhenIdle(rulesText);
      void this.updateRulesIfNeeded();
      return true;
    } catch (error) {
      Logger.error(TAG, `Failed to load ad rules: ${String(error)}`);
      return false;
    }
  }

  private compileWhenIdle(rulesText: string): void {
    setTimeout((): void => {
      try {
        AdsBlockService.adopt(RuleEngine.compile(rulesText), rulesText);
        Logger.info(TAG, `Compiled ${AdsBlockService.compiledEngine?.ruleCount ?? 0} ad rules`);
      } catch (error) {
        Logger.error(TAG, `Failed to compile ad rules: ${String(error)}`);
      }
    }, 0);
  }

  /**
   * The compiled rules are process-wide on purpose: every web view constructs
   * its own AdsBlockService and none of them run initialize, so an instance
   * field would leave interception reading an empty engine.
   */
  private static adopt(engine: RuleEngine, rulesText: string): void {
    AdsBlockService.compiledEngine = engine;
    AdsBlockService.cosmeticFilter = CosmeticFilterService.compile(rulesText);
  }

  shouldBlock(context: RuleMatchContext): boolean {
    return AdsBlockService.compiledEngine?.shouldBlock(context) ?? false;
  }

  static cosmeticScriptFor(pageUrl: string): string {
    return AdsBlockService.cosmeticFilter?.scriptFor(pageUrl) ?? '';
  }

  interceptRequest(
    request: WebResourceRequest,
    pageUrl: string,
    enabled: boolean
  ): WebResourceResponse | null {
    // The top-level document is never an ad: answering it with a blocked
    // response aborts the navigation and leaves the tab blank.
    if (!enabled || request.isMainFrame()) {
      return null;
    }
    const url: string = request.getRequestUrl();
    if (!this.shouldBlock({
      url: url,
      pageUrl: pageUrl,
      resourceType: AdsBlockService.resourceTypeOf(request, url)
    })) {
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

  /**
   * ArkWeb does not tell us what a request is for, but roughly a third of
   * EasyList's option-carrying rules are scoped to a resource type and match
   * nothing without one. The Accept header is authoritative when the browser
   * sends a specific one; the extension is the fallback, and `other` is the
   * honest answer when neither says anything — it simply leaves typed rules
   * inapplicable rather than misapplying them.
   */
  private static resourceTypeOf(request: WebResourceRequest, url: string): string {
    const accept: string = AdsBlockService.header(request, 'accept').toLowerCase();
    if (accept.includes('text/css')) {
      return 'stylesheet';
    }
    if (accept.startsWith('image/') || accept.includes('image/webp') || accept.includes('image/avif')) {
      return 'image';
    }
    if (accept.includes('text/html') || accept.includes('application/xhtml')) {
      return 'subdocument';
    }
    if (accept.includes('font/') || accept.includes('application/font')) {
      return 'font';
    }
    if (AdsBlockService.header(request, 'x-requested-with').toLowerCase() === 'xmlhttprequest') {
      return 'xmlhttprequest';
    }
    return AdsBlockService.resourceTypeFromPath(url);
  }

  private static resourceTypeFromPath(url: string): string {
    const path: string = url.split('#')[0].split('?')[0].toLowerCase();
    const dot: number = path.lastIndexOf('.');
    const slash: number = path.lastIndexOf('/');
    if (dot < 0 || dot < slash) {
      return 'other';
    }
    const extension: string = path.slice(dot + 1);
    if (extension === 'js' || extension === 'mjs') {
      return 'script';
    }
    if (extension === 'css') {
      return 'stylesheet';
    }
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp', 'avif'].includes(extension)) {
      return 'image';
    }
    if (['woff', 'woff2', 'ttf', 'otf', 'eot'].includes(extension)) {
      return 'font';
    }
    if (['mp4', 'webm', 'm4v', 'mp3', 'ogg', 'wav', 'm3u8', 'ts'].includes(extension)) {
      return 'media';
    }
    if (extension === 'json') {
      return 'xmlhttprequest';
    }
    if (extension === 'html' || extension === 'htm') {
      return 'subdocument';
    }
    return 'other';
  }

  private static header(request: WebResourceRequest, name: string): string {
    try {
      for (const header of request.getRequestHeader()) {
        if (header.headerKey.toLowerCase() === name) {
          return header.headerValue;
        }
      }
    } catch (_error) {
      // Headers are unavailable for some internal requests.
    }
    return '';
  }

  get ruleCount(): number {
    return AdsBlockService.compiledEngine?.ruleCount ?? 0;
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
    try {
      const rulesText: string = await AdsBlockService.fetchRemoteRules();
      const engine: RuleEngine = RuleEngine.compile(rulesText);
      if (rulesText.trim().length === 0 || engine.ruleCount === 0) {
        throw new Error('Remote rules are empty');
      }
      await this.writeRulesAtomically(rulesText);
      AdsBlockService.adopt(engine, rulesText);
      webview.AdsBlockManager.setAdsBlockRules(this.rulesPath, true);
      this.updatedAt = Date.now();
      await this.saveUpdatedAt(this.updatedAt);
      Logger.info(TAG, `Updated ${engine.ruleCount} ad rules`);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Failed to update ad rules; keeping the current list: ${String(error)}`);
      return false;
    } finally {
      this.updating = false;
    }
  }

  private static async readBundledRules(context: common.UIAbilityContext): Promise<string> {
    const decoder: util.TextDecoder = new util.TextDecoder();
    const parts: string[] = [];
    for (const source of RULE_SOURCES) {
      try {
        const content: Uint8Array = await context.resourceManager.getRawFileContent(source.rawfile);
        parts.push(decoder.decodeToString(content));
      } catch (error) {
        Logger.error(TAG, `Missing bundled rule file ${source.rawfile}: ${String(error)}`);
      }
    }
    return parts.join('\n');
  }

  /**
   * Every subscription has to arrive for the update to count. Taking a partial
   * set would silently narrow coverage — losing EasyList China, say — and the
   * result would then be cached as if it were complete.
   */
  private static async fetchRemoteRules(): Promise<string> {
    const parts: string[] = [];
    for (const source of RULE_SOURCES) {
      parts.push(await AdsBlockService.fetchRules(source.url));
    }
    return parts.join('\n');
  }

  private static async fetchRules(url: string): Promise<string> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 30000,
        header: { 'accept': 'text/plain' }
      });
      if (Number(response.responseCode) < 200 || Number(response.responseCode) >= 300) {
        throw new Error(`HTTP ${response.responseCode} for ${url}`);
      }
      const text: string = typeof response.result === 'string'
        ? response.result
        : new util.TextDecoder().decodeToString(new Uint8Array(response.result as ArrayBuffer));
      if (text.trim().length === 0) {
        throw new Error(`Empty response for ${url}`);
      }
      return text;
    } finally {
      request.destroy();
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

  private async readPersistedRules(fallback: string): Promise<string> {
    try {
      if (!await fs.access(this.rulesPath)) {
        return fallback;
      }
      const persisted: string = await fs.readText(this.rulesPath);
      return persisted.trim().length > 0 ? persisted : fallback;
    } catch (_error) {
      return fallback;
    }
  }

  private async readUpdatedAt(): Promise<number> {
    try {
      if (!await fs.access(this.updatedAtPath)) {
        return 0;
      }
      const value: number = Number(await fs.readText(this.updatedAtPath));
      return Number.isFinite(value) && value > 0 ? value : 0;
    } catch (_error) {
      return 0;
    }
  }

  private async saveUpdatedAt(value: number): Promise<void> {
    try {
      await AdsBlockService.writeText(this.updatedAtPath, `${value}`);
    } catch (error) {
      Logger.warn(TAG, `Failed to save ad rules update time: ${String(error)}`);
    }
  }

  private static async writeText(path: string, text: string): Promise<void> {
    const file: fs.File = await fs.open(
      path,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
    );
    try {
      await fs.write(file.fd, text);
    } finally {
      await fs.close(file.fd);
    }
  }

  private async writeRulesAtomically(rulesText: string): Promise<void> {
    const temporaryPath: string = `${this.rulesPath}.next`;
    try {
      await AdsBlockService.writeText(temporaryPath, rulesText);
      await fs.rename(temporaryPath, this.rulesPath);
    } catch (error) {
      try {
        if (await fs.access(temporaryPath)) {
          await fs.unlink(temporaryPath);
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
