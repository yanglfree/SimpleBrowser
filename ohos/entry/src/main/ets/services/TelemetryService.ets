import { bundleManager, common, errorManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { http } from '@kit.NetworkKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import { Logger } from '../utils/Logger';
import {
  ReaderExtractionReport,
  ReaderExtractionBuckets,
  readerExtractionBuckets
} from '../models/ReaderExtractionModels';
import { allowsTelemetryWrite } from './TelemetryPolicy';
import {
  ShuYiShuAnalytics,
  ShuYiShuDeviceContext,
  ShuYiShuDeviceKind,
  ShuYiShuJsonObject,
  ShuYiShuPropertyEntry,
  ShuYiShuStorage,
  ShuYiShuTransport,
  ShuYiShuTransportRequest,
  ShuYiShuTransportResponse
} from './ShuYiShuAnalytics';

const TAG: string = 'TelemetryService';
const EVENT_DOMAIN: string = 'dolphin_browser';
const SHUYISHU_BASE_URL: string = 'https://trending.youdroid.top';
const SHUYISHU_PRODUCT_ID: string = 'product-zhuobrowser';
const SHUYISHU_APP_KEY: string = 'prod_zhuobrowser_harmony';
const SHUYISHU_PREF_FILE: string = 'shuyishu_zhuobrowser';
const SHUYISHU_INSTALL_ID_KEY: string = 'shuyishu_zhuobrowser_installation_id';
const SHUYISHU_QUEUE_KEY: string = 'shuyishu_event_queue';
const SHUYISHU_FIRST_OPEN_KEY: string = 'shuyishu_first_open_at';
const SHUYISHU_LAST_VERSION_KEY: string = 'shuyishu_last_app_version';

interface CrashPayload {
  kind: string;
  name: string;
}

interface PageLoadPayload {
  duration_ms: number;
}

interface StartupPayload {
  duration_ms: number;
}

interface MemoryPayload {
  level: number;
}

interface ActionUsagePayload {
  action: string;
}

interface ReaderPayload {
  result: string;
  strategy: string;
  candidate_chars: string;
  output_ratio: string;
  paragraphs: string;
  image_count: number;
  duration_ms: number;
}

class PreferenceShuYiShuStorage implements ShuYiShuStorage {
  private pref?: preferences.Preferences;
  private values: Map<string, string> = new Map();

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, SHUYISHU_PREF_FILE);
      await this.loadKey(SHUYISHU_INSTALL_ID_KEY);
      await this.loadKey(SHUYISHU_QUEUE_KEY);
      await this.loadKey(SHUYISHU_FIRST_OPEN_KEY);
      await this.loadKey(SHUYISHU_LAST_VERSION_KEY);
    } catch (error) {
      this.pref = undefined;
      Logger.warn(TAG, `ShuYiShu preferences unavailable: ${String(error)}`);
    }
  }

  getString(key: string): string | undefined {
    return this.values.get(key);
  }

  setString(key: string, value: string): void {
    this.values.set(key, value);
    const store: preferences.Preferences | undefined = this.pref;
    if (store === undefined) {
      return;
    }
    store.put(key, value).then((): Promise<void> => {
      return store.flush();
    }).catch((error: Error): void => {
      Logger.warn(TAG, `ShuYiShu persist ${key} failed: ${String(error)}`);
    });
  }

  installationId(): string {
    const existing: string | undefined = this.values.get(SHUYISHU_INSTALL_ID_KEY);
    if (existing !== undefined && existing.length > 0) {
      return existing;
    }
    const created: string = `zhuobrowser_harmony_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    this.setString(SHUYISHU_INSTALL_ID_KEY, created);
    return created;
  }

  private async loadKey(key: string): Promise<void> {
    const store: preferences.Preferences | undefined = this.pref;
    if (store === undefined) {
      return;
    }
    try {
      const value: preferences.ValueType = await store.get(key, '');
      if (typeof value === 'string' && value.length > 0) {
        this.values.set(key, value);
      }
    } catch (_) {
      // Ignore single-key load errors so cached values degrade cleanly.
    }
  }
}

class HttpShuYiShuTransport implements ShuYiShuTransport {
  async postJson(request: ShuYiShuTransportRequest): Promise<ShuYiShuTransportResponse> {
    if (!request.url.startsWith('https://')) {
      throw new Error(`Refusing non-HTTPS analytics URL: ${request.url}`);
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(request.url, {
        method: http.RequestMethod.POST,
        header: request.headers,
        extraData: request.body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      });
      return {
        statusCode: Number(response.responseCode),
        body: typeof response.result === 'string' ? response.result : ''
      };
    } finally {
      client.destroy();
    }
  }
}

/**
 * Privacy-friendly telemetry. Hard rules:
 *
 * 1. System diagnostics continue writing to hiAppEvent, while consented events also
 *    sync to ShuYiShu without URLs, domains, page contents, or search queries.
 * 2. Crash payloads carry only the exception category and name.
 * 3. A private tab suppresses every write and lifecycle flush.
 */
export class TelemetryService {
  private static registered: boolean = false;
  private static initializing: boolean = false;
  private static initialized: boolean = false;
  private static enabled: boolean = false;
  private static privateContext: boolean = false;
  private static consentResolved: boolean = false;
  private static pendingStartupMs: number | undefined = undefined;
  private static readonly storage: PreferenceShuYiShuStorage = new PreferenceShuYiShuStorage();
  private static client?: ShuYiShuAnalytics;
  private static pendingForeground: boolean = false;

  static initialize(context: common.UIAbilityContext): void {
    if (TelemetryService.initialized || TelemetryService.initializing) {
      return;
    }
    TelemetryService.initializing = true;
    TelemetryService.storage.init(context).then((): void => {
      let appVersion: string = '1.0.0';
      let buildNumber: string = '1';
      try {
        const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
          bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
        );
        if (bundleInfo.versionName.length > 0) {
          appVersion = bundleInfo.versionName;
        }
        buildNumber = String(bundleInfo.versionCode);
      } catch (error) {
        Logger.warn(TAG, `Bundle metadata unavailable: ${String(error)}`);
      }

      const rawType: string = deviceInfo.deviceType ?? 'unknown';
      const kind: ShuYiShuDeviceKind = TelemetryService.mapDeviceKind(rawType);
      const deviceContext: ShuYiShuDeviceContext = {
        kind: kind,
        raw_type: rawType,
        os: 'HarmonyOS',
        os_version: deviceInfo.osFullName ?? ''
      };

      const locale: string = TelemetryService.resolveLocale();
      const timezone: string = TelemetryService.resolveTimezone();

      const client = new ShuYiShuAnalytics({
        baseUrl: SHUYISHU_BASE_URL,
        appKey: SHUYISHU_APP_KEY,
        productId: SHUYISHU_PRODUCT_ID,
        platform: 'harmony',
        appVersion: appVersion,
        buildNumber: buildNumber,
        installationId: TelemetryService.storage.installationId(),
        locale: locale,
        timezone: timezone,
        device: deviceContext,
        transport: new HttpShuYiShuTransport(),
        storage: TelemetryService.storage,
        consentState: TelemetryService.enabled ? 'granted' : 'denied'
      });
      TelemetryService.client = client;
      TelemetryService.initialized = true;
      TelemetryService.initializing = false;

      if (TelemetryService.pendingForeground &&
        allowsTelemetryWrite(TelemetryService.enabled, TelemetryService.privateContext)) {
        TelemetryService.pendingForeground = false;
        client.handleAppForegrounded();
      }
    }).catch((error: Error): void => {
      TelemetryService.initializing = false;
      Logger.warn(TAG, `ShuYiShu init failed: ${String(error)}`);
    });
  }

  /** Set from the privacy settings; off disables every write immediately. */
  static setEnabled(enabled: boolean): void {
    TelemetryService.enabled = enabled;
    TelemetryService.consentResolved = true;
    TelemetryService.client?.setConsent(enabled ? 'granted' : 'denied');
    const pendingStartupMs: number | undefined = TelemetryService.pendingStartupMs;
    TelemetryService.pendingStartupMs = undefined;
    if (enabled && pendingStartupMs !== undefined) {
      const clamped: number = TelemetryService.clamp(pendingStartupMs);
      const payload: StartupPayload = { duration_ms: clamped };
      TelemetryService.writeEvent('startup', payload);
      TelemetryService.trackShuYiShu('app_startup', { duration_ms: clamped });
    }
    Logger.info(TAG, `Telemetry ${enabled ? 'enabled' : 'disabled'}`);
  }

  /** Called whenever the focused tab changes. Private browsing is a hard stop. */
  static setPrivateContext(privateContext: boolean): void {
    TelemetryService.privateContext = privateContext;
  }

  static handleAppForegrounded(): void {
    if (!allowsTelemetryWrite(TelemetryService.enabled, TelemetryService.privateContext)) {
      return;
    }
    const client: ShuYiShuAnalytics | undefined = TelemetryService.client;
    if (client === undefined) {
      TelemetryService.pendingForeground = true;
      return;
    }
    client.setConsent('granted');
    client.handleAppForegrounded();
  }

  static handleAppBackgrounded(): void {
    if (!allowsTelemetryWrite(TelemetryService.enabled, TelemetryService.privateContext)) {
      return;
    }
    const client: ShuYiShuAnalytics | undefined = TelemetryService.client;
    if (client === undefined) {
      return;
    }
    client.handleAppBackgrounded().then((): Promise<void> => {
      return client.flush();
    }).catch((error: Error): void => {
      Logger.warn(TAG, `ShuYiShu background flush failed: ${String(error)}`);
    });
  }

  static registerCrashObservers(): void {
    if (TelemetryService.registered) {
      return;
    }
    TelemetryService.registered = true;

    try {
      errorManager.on('error', new CrashErrorObserver());
    } catch (error) {
      Logger.warn(TAG, `Error observer unavailable: ${String(error)}`);
    }

    try {
      errorManager.on('unhandledRejection', (reason: Error | undefined): void => {
        const err: Error = reason instanceof Error ? reason : new Error(String(reason));
        TelemetryService.reportCrash('unhandled_rejection', err);
      });
    } catch (error) {
      Logger.warn(TAG, `Rejection observer unavailable: ${String(error)}`);
    }
  }

  /** Startup is measured from ability creation to first page load. */
  static recordStartup(ms: number): void {
    if (!TelemetryService.consentResolved) {
      TelemetryService.pendingStartupMs = TelemetryService.clamp(ms);
      return;
    }
    const clamped: number = TelemetryService.clamp(ms);
    const payload: StartupPayload = { duration_ms: clamped };
    TelemetryService.writeEvent('startup', payload);
    TelemetryService.trackShuYiShu('app_startup', { duration_ms: clamped });
  }

  /** Records page-load duration without any page location. */
  static recordPageLoad(ms: number): void {
    if (ms < 0) {
      return;
    }
    const clamped: number = TelemetryService.clamp(ms);
    const payload: PageLoadPayload = {
      duration_ms: clamped
    };
    TelemetryService.writeEvent('page_load', payload);
    TelemetryService.trackShuYiShu('page_load', { duration_ms: clamped });
  }

  /** Tab memory pressure downgrade, e.g. the app reclaimed background tabs. */
  static recordMemoryPressure(level: number): void {
    const payload: MemoryPayload = { level: level };
    TelemetryService.writeEvent('memory_pressure', payload);
    TelemetryService.trackShuYiShu('memory_pressure', { name: String(level) });
  }

  /** Records only coarse quality metrics, never a page location or article content. */
  static reportReaderExtraction(report: ReaderExtractionReport): void {
    const buckets: ReaderExtractionBuckets = readerExtractionBuckets(report);
    const clampedMs: number = TelemetryService.clamp(report.durationMs);
    const clampedImages: number = Math.min(1000, Math.max(0, report.imageCount));
    const payload: ReaderPayload = {
      result: report.result,
      strategy: report.strategy,
      candidate_chars: buckets.candidateChars,
      output_ratio: buckets.outputRatio,
      paragraphs: buckets.paragraphs,
      image_count: clampedImages,
      duration_ms: clampedMs
    };
    TelemetryService.writeEvent('reader_extraction', payload);
    const props: ShuYiShuJsonObject = {
      outcome: report.result,
      name: report.strategy,
      duration_ms: clampedMs
    };
    const extras: ShuYiShuPropertyEntry[] = [
      { key: 'candidate_chars', value: buckets.candidateChars },
      { key: 'output_ratio', value: buckets.outputRatio },
      { key: 'paragraphs', value: buckets.paragraphs },
      { key: 'image_count', value: clampedImages }
    ];
    TelemetryService.trackShuYiShu('reader_extraction', props, extras);
  }

  static reportCrash(name: string, error: Error): void {
    const errorName: string = error.name ?? 'Error';
    const payload: CrashPayload = {
      kind: name,
      name: errorName
    };
    TelemetryService.writeEvent('crash', payload);
    TelemetryService.trackShuYiShu('crash', {
      error_category: name,
      name: errorName
    });
  }

  /** Menu/quick-action invocation; feeds the usage-ranking design without PII. */
  static reportActionUsage(key: string): void {
    if (key.length === 0) {
      return;
    }
    const action: string = TelemetryService.trim(key, 40);
    const payload: ActionUsagePayload = { action: action };
    TelemetryService.writeEvent('action_usage', payload);
    TelemetryService.trackShuYiShu('action_usage', { action: action });
  }

  private static writeEvent(eventName: string, params: Object): void {
    if (!allowsTelemetryWrite(TelemetryService.enabled, TelemetryService.privateContext)) {
      if (TelemetryService.enabled && TelemetryService.privateContext) {
        Logger.info(TAG, `Suppressed ${eventName} in private context`);
      }
      return;
    }
    const info: hiAppEvent.AppEventInfo = {
      domain: EVENT_DOMAIN,
      name: eventName,
      eventType: hiAppEvent.EventType.STATISTIC,
      params: params
    };
    hiAppEvent.write(info).catch((error: Error): void => {
      Logger.warn(TAG, `Event ${eventName} failed: ${String(error)}`);
    });
  }

  private static trackShuYiShu(
    eventName: string,
    props: ShuYiShuJsonObject,
    extras?: ShuYiShuPropertyEntry[]
  ): void {
    if (!allowsTelemetryWrite(TelemetryService.enabled, TelemetryService.privateContext)) {
      return;
    }
    const client: ShuYiShuAnalytics | undefined = TelemetryService.client;
    if (client === undefined) {
      return;
    }
    client.setConsent('granted');
    client.track(eventName, props, extras);
  }

  private static mapDeviceKind(rawType: string): ShuYiShuDeviceKind {
    const lowered: string = rawType.toLowerCase();
    if (lowered === 'phone') {
      return 'phone';
    }
    if (lowered === 'tablet') {
      return 'pad';
    }
    if (lowered === '2in1') {
      return 'desktop';
    }
    return 'unknown';
  }

  private static resolveLocale(): string {
    try {
      return i18n.System.getSystemLocale();
    } catch (_) {
      return 'zh-CN';
    }
  }

  private static resolveTimezone(): string {
    try {
      return i18n.getTimeZone().getID();
    } catch (_) {
      return 'Asia/Shanghai';
    }
  }

  private static clamp(ms: number): number {
    if (!Number.isFinite(ms) || ms < 0) {
      return 0;
    }
    return Math.round(ms);
  }

  private static trim(value: string, max: number): string {
    return value.length <= max ? value : value.slice(0, max);
  }
}

/** errorManager.ErrorObserver is a class in this SDK; extend it to register. */
class CrashErrorObserver {
  onUnhandledException(errMsg: string): void {
    TelemetryService.reportCrash('uncaught_exception', new Error(errMsg));
  }
}
