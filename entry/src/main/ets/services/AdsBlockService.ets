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
  name: string;
  /**
   * Snapshot shipped in the HAP. Only the two lists the browser cannot sensibly
   * run without carry one — bundling every subscription would add megabytes to
   * the package to cover the minutes before the first refresh lands.
   */
  rawfile?: string;
  url: string;
  /**
   * A failed fetch of a required list abandons the refresh and keeps the list
   * already in use. The rest are best-effort: one unreachable host must not
   * cost the user every other update, and some of these are not reliably
   * reachable from the mainland.
   */
  required: boolean;
}

/**
 * The subscriptions the browser blocks with. EasyList is the base and EasyList
 * China covers what it misses on Chinese sites; both ship in the HAP so a cold
 * install blocks something before its first refresh. The rest arrive over the
 * network: EasyPrivacy for trackers, AdGuard's Chinese list (a superset of
 * EasyList China maintained on a faster cycle), and CJX's list for the
 * mainland-specific nags neither of the others carries. Everything is
 * concatenated into the single file ArkWeb's native blocker reads.
 */
const RULE_SOURCES: RuleSource[] = [
  {
    name: 'EasyList',
    rawfile: 'ads/easylist.txt',
    url: 'https://easylist-downloads.adblockplus.org/easylist.txt',
    required: true
  },
  {
    name: 'EasyList China',
    rawfile: 'ads/easylistchina.txt',
    url: 'https://easylist-downloads.adblockplus.org/easylistchina.txt',
    required: true
  },
  {
    name: 'EasyPrivacy',
    url: 'https://easylist-downloads.adblockplus.org/easyprivacy.txt',
    required: false
  },
  {
    name: 'AdGuard Chinese',
    url: 'https://filters.adtidy.org/extension/ublock/filters/224.txt',
    required: false
  },
  {
    name: "CJX's Annoyance",
    // Served through jsDelivr rather than raw.githubusercontent.com, which is
    // not reachable from the mainland — on the test device that source was
    // skipped on every refresh.
    url: 'https://cdn.jsdelivr.net/gh/cjx82630/cjxlist@master/cjx-annoyance.txt',
    required: false
  }
];

/**
 * Our own rules for what the subscriptions miss. It has no upstream to fetch,
 * and the list the browser actually runs on may come from disk or the network
 * rather than the HAP, so it is fenced with markers and re-applied to whatever
 * text is in hand: strip the old region, append the shipped one. Without that
 * the supplement would only ever reach a device that had never stored a list.
 */
const SUPPLEMENT_RAWFILE: string = 'ads/dolphin-supplement.txt';
const SUPPLEMENT_BEGIN: string = '! >>> dolphin-supplement';
const SUPPLEMENT_END: string = '! <<< dolphin-supplement';
const SUPPLEMENT_FILE_NAME: string = 'dolphin-supplement.txt';
/**
 * Where the supplement is published, if it is. Point this at the hosted copy to
 * answer "site X still shows ads" by adding a selector and refreshing rather
 * than by shipping a release; leave it empty and the copy in the HAP is used.
 * A fetched copy is kept on disk, so it survives a restart without the network.
 */
const SUPPLEMENT_URL: string = '';

export class AdsBlockService {
  private static compiledEngine: RuleEngine | undefined;
  private static cosmeticFilter: CosmeticFilterService | undefined;
  /** Read once from the HAP, re-appended after every remote refresh. */
  private static supplement: string = '';
  private rulesPath: string = '';
  private updatedAtPath: string = '';
  private supplementPath: string = '';
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
      this.supplementPath = `${context.filesDir}/${SUPPLEMENT_FILE_NAME}`;
      AdsBlockService.supplement = await this.readSupplement(context);
      const rulesText: string = AdsBlockService.withSupplement(
        await this.readPersistedRules(await AdsBlockService.readBundledRules(context))
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
      await this.updateSupplement();
      const rulesText: string = AdsBlockService.withSupplement(
        AdsBlockService.dedupe(await AdsBlockService.fetchRemoteRules())
      );
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
    const parts: string[] = [];
    for (const source of RULE_SOURCES) {
      const rawfile: string | undefined = source.rawfile;
      if (rawfile !== undefined) {
        parts.push(await AdsBlockService.readRawFile(context, rawfile));
      }
    }
    return parts.join('\n');
  }

  /**
   * The newest supplement we have: the one fetched last, else the one in the
   * HAP. A hosted copy that fails to parse as rules would be worse than none,
   * so a stored copy that has gone empty falls back to the bundled text.
   */
  private async readSupplement(context: common.UIAbilityContext): Promise<string> {
    const bundled: string = await AdsBlockService.readRawFile(context, SUPPLEMENT_RAWFILE);
    try {
      if (!await fs.access(this.supplementPath)) {
        return bundled;
      }
      const stored: string = await fs.readText(this.supplementPath);
      return stored.trim().length > 0 ? stored : bundled;
    } catch (_error) {
      return bundled;
    }
  }

  /** Refreshes the supplement from its own URL, when one is configured. */
  private async updateSupplement(): Promise<void> {
    if (SUPPLEMENT_URL.length === 0) {
      return;
    }
    try {
      const text: string = await AdsBlockService.fetchRules(SUPPLEMENT_URL);
      AdsBlockService.supplement = text;
      await AdsBlockService.writeText(this.supplementPath, text);
      Logger.info(TAG, 'Supplement updated');
    } catch (error) {
      Logger.warn(TAG, `Keeping the current supplement: ${String(error)}`);
    }
  }

  /** Replaces any previously appended supplement with the one shipped now. */
  private static withSupplement(rulesText: string): string {
    const begin: number = rulesText.indexOf(SUPPLEMENT_BEGIN);
    const end: number = rulesText.lastIndexOf(SUPPLEMENT_END);
    const base: string = begin >= 0 && end > begin
      ? rulesText.slice(0, begin) + rulesText.slice(end + SUPPLEMENT_END.length)
      : rulesText;
    if (AdsBlockService.supplement.trim().length === 0) {
      return base;
    }
    return `${base.trimEnd()}\n${SUPPLEMENT_BEGIN}\n${AdsBlockService.supplement.trim()}\n${SUPPLEMENT_END}\n`;
  }

  private static async readRawFile(context: common.UIAbilityContext, path: string): Promise<string> {
    try {
      const content: Uint8Array = await context.resourceManager.getRawFileContent(path);
      return new util.TextDecoder().decodeToString(content);
    } catch (error) {
      Logger.error(TAG, `Missing bundled rule file ${path}: ${String(error)}`);
      return '';
    }
  }

  /**
   * Every subscription has to arrive for the update to count. Taking a partial
   * set would silently narrow coverage — losing EasyList China, say — and the
   * result would then be cached as if it were complete.
   */
  private static async fetchRemoteRules(): Promise<string> {
    const parts: string[] = [];
    for (const source of RULE_SOURCES) {
      try {
        parts.push(await AdsBlockService.fetchRules(source.url));
      } catch (error) {
        if (source.required) {
          throw new Error(`${source.name} is unavailable: ${String(error)}`);
        }
        Logger.warn(TAG, `Skipping ${source.name}: ${String(error)}`);
      }
    }
    return parts.join('\n');
  }

  /**
   * The subscriptions overlap — AdGuard's Chinese list contains EasyList China
   * outright — so identical lines are collapsed before anything parses them.
   * That shrinks what ArkWeb reads, what the engine compiles, and what both
   * hold afterwards, for one pass over the text.
   */
  private static dedupe(rulesText: string): string {
    const seen: Set<string> = new Set<string>();
    const kept: string[] = [];
    for (const line of rulesText.split('\n')) {
      const trimmed: string = line.trim();
      if (trimmed.length === 0) {
        continue;
      }
      // Comments carry list titles and the supplement's fences; they are cheap
      // and worth keeping intact.
      if (trimmed.startsWith('!')) {
        kept.push(trimmed);
        continue;
      }
      if (!seen.has(trimmed)) {
        seen.add(trimmed);
        kept.push(trimmed);
      }
    }
    return kept.join('\n');
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
