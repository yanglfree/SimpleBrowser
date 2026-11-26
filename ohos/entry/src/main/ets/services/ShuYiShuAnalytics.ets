export type ShuYiShuPlatform = 'ios' | 'android' | 'harmony' | 'web' | 'macos';
export type ShuYiShuConsentState = 'granted' | 'denied' | 'unknown';
export type ShuYiShuDeviceKind = 'phone' | 'pad' | 'foldable' | 'desktop' | 'unknown';
export type ShuYiShuJsonPrimitive = string | number | boolean | null;
export type ShuYiShuJsonValue = ShuYiShuJsonPrimitive | ShuYiShuJsonValue[];

export interface ShuYiShuPropertyEntry {
  key: string;
  value: ShuYiShuJsonValue;
}

export interface ShuYiShuDeviceContext {
  kind: ShuYiShuDeviceKind;
  raw_type?: string;
  os?: string;
  os_version?: string;
  screen_bucket?: string;
}

export interface ShuYiShuAppContext {
  build_mode?: string;
  distribution?: string;
  first_open_at?: string;
  is_first_launch?: boolean;
  install_age_days?: number;
  previous_app_version?: string;
}

export interface ShuYiShuNetworkContext {
  type?: string;
}

export interface ShuYiShuDebugContext {
  build_mode?: string;
  is_simulator?: boolean;
}

export interface ShuYiShuJsonObject {
  screen?: ShuYiShuJsonValue;
  previous_screen?: ShuYiShuJsonValue;
  dwell_ms?: ShuYiShuJsonValue;
  name?: ShuYiShuJsonValue;
  feature?: ShuYiShuJsonValue;
  source?: ShuYiShuJsonValue;
  tab?: ShuYiShuJsonValue;
  surface?: ShuYiShuJsonValue;
  section?: ShuYiShuJsonValue;
  action?: ShuYiShuJsonValue;
  outcome?: ShuYiShuJsonValue;
  error_category?: ShuYiShuJsonValue;
  latency_ms?: ShuYiShuJsonValue;
  duration_ms?: ShuYiShuJsonValue;
  event_count?: ShuYiShuJsonValue;
  screen_count?: ShuYiShuJsonValue;
  last_screen?: ShuYiShuJsonValue;
  end_reason?: ShuYiShuJsonValue;
}

export interface ShuYiShuHeaders {
  'content-type': string;
}

export interface ShuYiShuAnalyticsOptions {
  baseUrl: string;
  appKey: string;
  productId: string;
  platform: ShuYiShuPlatform;
  appVersion: string;
  buildNumber: string;
  installationId: string;
  locale: string;
  country?: string;
  device?: ShuYiShuDeviceContext;
  app?: ShuYiShuAppContext;
  network?: ShuYiShuNetworkContext;
  debug?: ShuYiShuDebugContext;
  timezone: string;
  transport: ShuYiShuTransport;
  storage?: ShuYiShuStorage;
  consentState?: ShuYiShuConsentState;
  maxQueueSize?: number;
  maxBatchSize?: number;
  maxPayloadBytes?: number;
  sessionTimeoutMs?: number;
  retryAttempts?: number;
  retryBaseDelayMs?: number;
  now?: () => Date;
  createId?: () => string;
  delay?: (durationMs: number) => Promise<void>;
}

export interface ShuYiShuTransportRequest {
  url: string;
  headers: ShuYiShuHeaders;
  body: string;
}

export interface ShuYiShuTransportResponse {
  statusCode: number;
  body: string;
}

export interface ShuYiShuTransport {
  postJson(request: ShuYiShuTransportRequest): Promise<ShuYiShuTransportResponse>;
}

export interface ShuYiShuStorage {
  getString(key: string): string | undefined;
  setString(key: string, value: string): void;
}

export interface ShuYiShuEvent {
  event_schema_version: 1;
  event_id: string;
  event_name: string;
  product_id: string;
  app_key: string;
  platform: ShuYiShuPlatform;
  app_version: string;
  build_number: string;
  anonymous_installation_id: string;
  anonymous_user_id?: string;
  session_id?: string;
  timestamp: string;
  timezone: string;
  locale: string;
  country?: string;
  properties: ShuYiShuJsonObject;
  extra_properties?: ShuYiShuPropertyEntry[];
  consent_state: ShuYiShuConsentState;
  sdk_name: 'shuyishu-harmony';
  sdk_version: string;
  device?: ShuYiShuDeviceContext;
  app?: ShuYiShuAppContext;
  network?: ShuYiShuNetworkContext;
  debug?: ShuYiShuDebugContext;
}

interface ShuYiShuBatchSlice {
  body: string;
  eventCount: number;
}

export class ShuYiShuIngestionError extends Error {
  public readonly statusCode: number;

  public constructor(statusCode: number) {
    super(`Shu Yi Shu ingestion failed: ${statusCode}`);
    this.statusCode = statusCode;
  }

  public get isRetryable(): boolean {
    return isRetryableStatusCode(this.statusCode);
  }
}

export class ShuYiShuEventTooLargeError extends Error {
  public readonly actualBytes: number;
  public readonly maxBytes: number;

  public constructor(actualBytes: number, maxBytes: number) {
    super(`Shu Yi Shu event too large: ${actualBytes} bytes exceeds ${maxBytes}`);
    this.actualBytes = actualBytes;
    this.maxBytes = maxBytes;
  }
}

const EVENT_SCHEMA_VERSION: 1 = 1;
const SDK_NAME: 'shuyishu-harmony' = 'shuyishu-harmony';
const SDK_VERSION: string = '0.3.0';
const DEFAULT_MAX_QUEUE_SIZE: number = 500;
const DEFAULT_MAX_BATCH_SIZE: number = 100;
const DEFAULT_MAX_PAYLOAD_BYTES: number = 32 * 1024;
const DEFAULT_SESSION_TIMEOUT_MS: number = 30_000;
const DEFAULT_RETRY_ATTEMPTS: number = 2;
const DEFAULT_RETRY_BASE_DELAY_MS: number = 500;
const QUEUE_STORAGE_KEY: string = 'shuyishu_event_queue';
const FIRST_OPEN_STORAGE_KEY: string = 'shuyishu_first_open_at';
const LAST_APP_VERSION_STORAGE_KEY: string = 'shuyishu_last_app_version';
const FORBIDDEN_PROPERTY_FRAGMENTS: string[] = [
  'access_token',
  'account_id',
  'anonymous_user_id',
  'error_message',
  'exception',
  'image',
  'login',
  'markdown',
  'private_repo',
  'query',
  'raw_error',
  'repo_name',
  'repository_name',
  'search_text',
  'source_code',
  'strokes',
  'text',
  'user_id',
];

function isForbiddenPropertyKey(key: string): boolean {
  const normalized: string = key.toLowerCase();
  for (let i: number = 0; i < FORBIDDEN_PROPERTY_FRAGMENTS.length; i += 1) {
    if (normalized.indexOf(FORBIDDEN_PROPERTY_FRAGMENTS[i]) !== -1) {
      return true;
    }
  }
  return false;
}

function isRetryableStatusCode(statusCode: number): boolean {
  return statusCode === 408 || statusCode === 425 || statusCode === 429 || statusCode >= 500;
}

function utf8ByteLength(text: string): number {
  let bytes: number = 0;
  for (let index: number = 0; index < text.length; index += 1) {
    const code: number = text.charCodeAt(index);
    if (code <= 0x7f) {
      bytes += 1;
    } else if (code <= 0x7ff) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
      const next: number = text.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

export class ShuYiShuAnalytics {
  private readonly options: ShuYiShuAnalyticsOptions;
  private readonly maxQueueSize: number;
  private readonly maxBatchSize: number;
  private readonly maxPayloadBytes: number;
  private readonly sessionTimeoutMs: number;
  private readonly retryAttempts: number;
  private readonly retryBaseDelayMs: number;
  private readonly now: () => Date;
  private readonly createId: () => string;
  private readonly delay: (durationMs: number) => Promise<void>;
  private queue: ShuYiShuEvent[] = [];
  private consentState: ShuYiShuConsentState;
  private country: string | undefined;
  private deviceContext: ShuYiShuDeviceContext | undefined;
  private appContext: ShuYiShuAppContext | undefined;
  private networkContext: ShuYiShuNetworkContext | undefined;
  private debugContext: ShuYiShuDebugContext | undefined;
  private superProperties: ShuYiShuPropertyEntry[] = [];
  private anonymousUserId: string | undefined = undefined;
  private sessionId: string | undefined = undefined;
  private sessionStartedAtMs: number | undefined = undefined;
  private sessionPausedAtMs: number | undefined = undefined;
  private lastScreenAtMs: number | undefined = undefined;
  private sessionLastScreen: string | undefined = undefined;
  private sessionEventCount: number = 0;
  private sessionScreenCount: number = 0;

  public constructor(options: ShuYiShuAnalyticsOptions) {
    this.options = options;
    this.maxQueueSize = options.maxQueueSize ?? DEFAULT_MAX_QUEUE_SIZE;
    this.maxBatchSize = options.maxBatchSize ?? DEFAULT_MAX_BATCH_SIZE;
    this.maxPayloadBytes = options.maxPayloadBytes ?? DEFAULT_MAX_PAYLOAD_BYTES;
    this.sessionTimeoutMs = options.sessionTimeoutMs ?? DEFAULT_SESSION_TIMEOUT_MS;
    this.retryAttempts = options.retryAttempts ?? DEFAULT_RETRY_ATTEMPTS;
    this.retryBaseDelayMs = options.retryBaseDelayMs ?? DEFAULT_RETRY_BASE_DELAY_MS;
    this.now = options.now ?? (() => new Date());
    this.createId = options.createId ?? (() => `evt_${Date.now()}_${Math.random().toString(16).slice(2)}`);
    this.delay = options.delay ?? ((durationMs: number) => {
      return new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, durationMs);
      });
    });
    this.consentState = options.consentState ?? 'unknown';
    this.country = this.normalizeCountry(options.country);
    this.deviceContext = options.device;
    this.appContext = this.resolveAppContext(options.app, options.appVersion, options.storage);
    this.networkContext = options.network;
    this.debugContext = options.debug;
    this.queue = this.loadQueue();
  }

  public get pendingCount(): number {
    return this.queue.length;
  }

  public setCountry(country: string | undefined): void {
    this.country = this.normalizeCountry(country);
  }

  public setDeviceContext(device: ShuYiShuDeviceContext | undefined): void {
    this.deviceContext = device;
  }

  public setNetworkContext(network: ShuYiShuNetworkContext | undefined): void {
    this.networkContext = network;
  }

  public setSuperProperty(key: string, value: ShuYiShuJsonValue | undefined): void {
    if (isForbiddenPropertyKey(key)) {
      return;
    }
    const filtered: ShuYiShuPropertyEntry[] = [];
    for (let i: number = 0; i < this.superProperties.length; i += 1) {
      if (this.superProperties[i].key !== key) {
        filtered.push(this.superProperties[i]);
      }
    }
    if (value !== undefined) {
      filtered.push({ key, value });
    }
    this.superProperties = filtered;
  }

  public clearSuperProperties(): void {
    this.superProperties = [];
  }

  public track(
    eventName: string,
    properties: ShuYiShuJsonObject = {},
    extraProperties?: ShuYiShuPropertyEntry[],
  ): void {
    this.enqueue(eventName, properties, undefined, extraProperties);
  }

  public trackEntries(eventName: string, entries: ShuYiShuPropertyEntry[]): void {
    this.enqueue(eventName, {}, undefined, entries);
  }

  public screen(
    screenName: string,
    properties: ShuYiShuJsonObject = {},
    extraProperties?: ShuYiShuPropertyEntry[],
  ): void {
    if (this.consentState !== 'granted') {
      return;
    }
    const nowMs: number = this.now().getTime();
    const merged: ShuYiShuJsonObject = this.cloneJsonObject(properties);
    if (this.sessionLastScreen !== undefined && this.sessionLastScreen !== screenName && merged.previous_screen === undefined) {
      merged.previous_screen = this.sessionLastScreen;
    }
    if (this.lastScreenAtMs !== undefined && merged.dwell_ms === undefined) {
      merged.dwell_ms = Math.max(0, nowMs - this.lastScreenAtMs);
    }
    merged.screen = screenName;

    this.sessionLastScreen = screenName;
    this.lastScreenAtMs = nowMs;
    if (this.sessionId !== undefined) {
      this.sessionScreenCount += 1;
    }

    this.enqueue('screen_view', merged, undefined, extraProperties);
  }

  public startSession(
    properties: ShuYiShuJsonObject = {},
    extraProperties?: ShuYiShuPropertyEntry[],
  ): void {
    if (this.consentState !== 'granted' || this.sessionId !== undefined) {
      return;
    }
    this.sessionId = this.createId();
    this.sessionStartedAtMs = this.now().getTime();
    this.sessionPausedAtMs = undefined;
    this.lastScreenAtMs = undefined;
    this.sessionLastScreen = undefined;
    this.sessionEventCount = 0;
    this.sessionScreenCount = 0;
    this.enqueue('session_start', properties, undefined, extraProperties);
  }

  public endSession(
    properties: ShuYiShuJsonObject = {},
    endedAtMs?: number,
    extraProperties?: ShuYiShuPropertyEntry[],
  ): void {
    const endingSessionId: string | undefined = this.sessionId;
    if (endingSessionId === undefined) {
      return;
    }

    const endMs: number = endedAtMs ?? this.now().getTime();
    const durationMs: number | undefined = this.sessionStartedAtMs !== undefined
      ? Math.max(0, endMs - this.sessionStartedAtMs)
      : undefined;
    const eventCount: number = this.sessionEventCount;
    const screenCount: number = this.sessionScreenCount;
    const lastScreen: string | undefined = this.sessionLastScreen;

    this.sessionId = undefined;
    this.sessionStartedAtMs = undefined;
    this.sessionPausedAtMs = undefined;
    this.lastScreenAtMs = undefined;
    this.sessionLastScreen = undefined;
    this.sessionEventCount = 0;
    this.sessionScreenCount = 0;

    const merged: ShuYiShuJsonObject = this.cloneJsonObject(properties);
    if (merged.event_count === undefined) {
      merged.event_count = eventCount;
    }
    if (merged.screen_count === undefined) {
      merged.screen_count = screenCount;
    }
    if (durationMs !== undefined && merged.duration_ms === undefined) {
      merged.duration_ms = durationMs;
    }
    if (lastScreen !== undefined && merged.last_screen === undefined) {
      merged.last_screen = lastScreen;
    }

    this.enqueue('session_end', merged, endingSessionId, extraProperties);
  }

  public async handleAppBackgrounded(): Promise<void> {
    if (this.consentState !== 'granted') {
      return;
    }
    if (this.sessionId !== undefined) {
      if (this.sessionPausedAtMs === undefined) {
        this.sessionPausedAtMs = this.now().getTime();
      }
      if (this.sessionTimeoutMs <= 0) {
        this.endSession({ end_reason: 'background_timeout' }, this.sessionPausedAtMs);
      }
    }
    try {
      await this.flush();
    } catch (_) {
      // Background flush failures stay queued for retry.
    }
  }

  public handleAppForegrounded(): boolean {
    if (this.consentState !== 'granted') {
      return false;
    }
    if (this.sessionId === undefined) {
      this.startSession();
      return true;
    }
    const pausedAtMs: number | undefined = this.sessionPausedAtMs;
    this.sessionPausedAtMs = undefined;
    if (pausedAtMs !== undefined && this.now().getTime() - pausedAtMs >= this.sessionTimeoutMs) {
      this.endSession({ end_reason: 'background_timeout' }, pausedAtMs);
      this.startSession();
      return true;
    }
    return false;
  }

  public setConsent(consentState: ShuYiShuConsentState): void {
    this.consentState = consentState;
    if (consentState === 'denied') {
      this.queue = [];
      this.superProperties = [];
      this.sessionId = undefined;
      this.sessionStartedAtMs = undefined;
      this.sessionPausedAtMs = undefined;
      this.lastScreenAtMs = undefined;
      this.sessionLastScreen = undefined;
      this.sessionEventCount = 0;
      this.sessionScreenCount = 0;
      this.anonymousUserId = undefined;
      this.persistQueue();
    }
  }

  public setUserId(userId: string): void {
    this.anonymousUserId = userId;
  }

  public clearUserId(): void {
    this.anonymousUserId = undefined;
  }

  public async flush(): Promise<void> {
    if (this.consentState !== 'granted' || this.queue.length === 0) {
      return;
    }

    while (this.queue.length > 0) {
      const batch: ShuYiShuBatchSlice = this.nextBatch();
      const events: ShuYiShuEvent[] = this.queue.slice(0, batch.eventCount);
      this.queue = this.queue.slice(batch.eventCount);
      this.persistQueue();

      try {
        await this.postBatchWithRetry(batch.body);
      } catch (error) {
        if (error instanceof ShuYiShuIngestionError && !error.isRetryable) {
          throw error;
        }
        this.restore(events);
        throw error instanceof Error ? error : new ShuYiShuIngestionError(0);
      }
    }
  }

  private enqueue(
    eventName: string,
    properties: ShuYiShuJsonObject,
    sessionIdOverride?: string,
    extraProperties?: ShuYiShuPropertyEntry[],
  ): void {
    if (this.consentState !== 'granted') {
      return;
    }

    const mergedExtra: ShuYiShuPropertyEntry[] = [];
    for (let i: number = 0; i < this.superProperties.length; i += 1) {
      const entry: ShuYiShuPropertyEntry = this.superProperties[i];
      if (!isForbiddenPropertyKey(entry.key)) {
        mergedExtra.push(entry);
      }
    }
    if (extraProperties !== undefined) {
      for (let i: number = 0; i < extraProperties.length; i += 1) {
        const entry: ShuYiShuPropertyEntry = extraProperties[i];
        if (!isForbiddenPropertyKey(entry.key)) {
          mergedExtra.push(entry);
        }
      }
    }

    const event: ShuYiShuEvent = {
      event_schema_version: EVENT_SCHEMA_VERSION,
      event_id: this.createId(),
      event_name: eventName,
      product_id: this.options.productId,
      app_key: this.options.appKey,
      platform: this.options.platform,
      app_version: this.options.appVersion,
      build_number: this.options.buildNumber,
      anonymous_installation_id: this.options.installationId,
      timestamp: this.now().toISOString(),
      timezone: this.options.timezone,
      locale: this.options.locale,
      properties,
      consent_state: this.consentState,
      sdk_name: SDK_NAME,
      sdk_version: SDK_VERSION,
    };

    if (mergedExtra.length > 0) {
      event.extra_properties = mergedExtra;
    }
    if (this.anonymousUserId !== undefined) {
      event.anonymous_user_id = this.anonymousUserId;
    }
    const activeSessionId: string | undefined = sessionIdOverride ?? this.sessionId;
    if (activeSessionId !== undefined) {
      event.session_id = activeSessionId;
    }
    if (this.country !== undefined) {
      event.country = this.country;
    }
    if (this.deviceContext !== undefined) {
      event.device = this.deviceContext;
    }
    if (this.appContext !== undefined) {
      event.app = this.appContext;
    }
    if (this.networkContext !== undefined) {
      event.network = this.networkContext;
    }
    if (this.debugContext !== undefined) {
      event.debug = this.debugContext;
    }

    const singleBytes: number = utf8ByteLength(this.encodeEnvelope([event]));
    if (singleBytes > this.maxPayloadBytes) {
      throw new ShuYiShuEventTooLargeError(singleBytes, this.maxPayloadBytes);
    }

    if (sessionIdOverride === undefined && this.sessionId !== undefined) {
      this.sessionEventCount += 1;
    }

    this.queue.push(event);
    while (this.queue.length > this.maxQueueSize) {
      this.queue.shift();
    }
    this.persistQueue();
  }

  private nextBatch(): ShuYiShuBatchSlice {
    const events: ShuYiShuEvent[] = [];
    let body: string = this.encodeEnvelope(events);
    const limit: number = Math.min(this.maxBatchSize, this.queue.length);

    for (let index: number = 0; index < limit; index += 1) {
      const item: ShuYiShuEvent = this.queue[index];
      const candidate: ShuYiShuEvent[] = [...events, item];
      const candidateBody: string = this.encodeEnvelope(candidate);
      if (utf8ByteLength(candidateBody) > this.maxPayloadBytes) {
        break;
      }
      events.push(item);
      body = candidateBody;
    }

    if (events.length === 0 && this.queue.length > 0) {
      const bytes: number = utf8ByteLength(this.encodeEnvelope([this.queue[0]]));
      throw new ShuYiShuEventTooLargeError(bytes, this.maxPayloadBytes);
    }

    return { body, eventCount: events.length };
  }

  private encodeEnvelope(events: ShuYiShuEvent[]): string {
    const items: string[] = [];
    for (let i: number = 0; i < events.length; i += 1) {
      items.push(this.encodeEvent(events[i]));
    }
    return `{"events":[${items.join(',')}],"sent_at":${JSON.stringify(this.now().toISOString())}}`;
  }

  private encodeEvent(event: ShuYiShuEvent): string {
    const propsJson: string = this.encodePropertiesJson(event.properties, event.extra_properties);
    const fields: string[] = [
      `"event_schema_version":${event.event_schema_version}`,
      `"event_id":${JSON.stringify(event.event_id)}`,
      `"event_name":${JSON.stringify(event.event_name)}`,
      `"product_id":${JSON.stringify(event.product_id)}`,
      `"app_key":${JSON.stringify(event.app_key)}`,
      `"platform":${JSON.stringify(event.platform)}`,
      `"app_version":${JSON.stringify(event.app_version)}`,
      `"build_number":${JSON.stringify(event.build_number)}`,
      `"anonymous_installation_id":${JSON.stringify(event.anonymous_installation_id)}`,
      `"timestamp":${JSON.stringify(event.timestamp)}`,
      `"timezone":${JSON.stringify(event.timezone)}`,
      `"locale":${JSON.stringify(event.locale)}`,
      `"properties":${propsJson}`,
      `"consent_state":${JSON.stringify(event.consent_state)}`,
      `"sdk_name":${JSON.stringify(event.sdk_name)}`,
      `"sdk_version":${JSON.stringify(event.sdk_version)}`,
    ];

    if (event.anonymous_user_id !== undefined) {
      fields.push(`"anonymous_user_id":${JSON.stringify(event.anonymous_user_id)}`);
    }
    if (event.session_id !== undefined) {
      fields.push(`"session_id":${JSON.stringify(event.session_id)}`);
    }
    if (event.country !== undefined) {
      fields.push(`"country":${JSON.stringify(event.country)}`);
    }
    if (event.device !== undefined) {
      fields.push(`"device":${JSON.stringify(event.device)}`);
    }
    if (event.app !== undefined) {
      fields.push(`"app":${JSON.stringify(event.app)}`);
    }
    if (event.network !== undefined) {
      fields.push(`"network":${JSON.stringify(event.network)}`);
    }
    if (event.debug !== undefined) {
      fields.push(`"debug":${JSON.stringify(event.debug)}`);
    }
    return `{${fields.join(',')}}`;
  }

  private encodePropertiesJson(
    properties: ShuYiShuJsonObject,
    extraProperties?: ShuYiShuPropertyEntry[],
  ): string {
    const pairs: string[] = [];
    this.pushOptionalJsonPair(pairs, 'screen', properties.screen);
    this.pushOptionalJsonPair(pairs, 'previous_screen', properties.previous_screen);
    this.pushOptionalJsonPair(pairs, 'dwell_ms', properties.dwell_ms);
    this.pushOptionalJsonPair(pairs, 'name', properties.name);
    this.pushOptionalJsonPair(pairs, 'feature', properties.feature);
    this.pushOptionalJsonPair(pairs, 'source', properties.source);
    this.pushOptionalJsonPair(pairs, 'tab', properties.tab);
    this.pushOptionalJsonPair(pairs, 'surface', properties.surface);
    this.pushOptionalJsonPair(pairs, 'section', properties.section);
    this.pushOptionalJsonPair(pairs, 'action', properties.action);
    this.pushOptionalJsonPair(pairs, 'outcome', properties.outcome);
    this.pushOptionalJsonPair(pairs, 'error_category', properties.error_category);
    this.pushOptionalJsonPair(pairs, 'latency_ms', properties.latency_ms);
    this.pushOptionalJsonPair(pairs, 'duration_ms', properties.duration_ms);
    this.pushOptionalJsonPair(pairs, 'event_count', properties.event_count);
    this.pushOptionalJsonPair(pairs, 'screen_count', properties.screen_count);
    this.pushOptionalJsonPair(pairs, 'last_screen', properties.last_screen);
    this.pushOptionalJsonPair(pairs, 'end_reason', properties.end_reason);

    if (extraProperties !== undefined) {
      for (let i: number = 0; i < extraProperties.length; i += 1) {
        const entry: ShuYiShuPropertyEntry = extraProperties[i];
        if (!isForbiddenPropertyKey(entry.key)) {
          pairs.push(`${JSON.stringify(entry.key)}:${JSON.stringify(entry.value)}`);
        }
      }
    }

    return `{${pairs.join(',')}}`;
  }

  private pushOptionalJsonPair(
    pairs: string[],
    key: string,
    value: ShuYiShuJsonValue | undefined,
  ): void {
    if (value !== undefined) {
      pairs.push(`${JSON.stringify(key)}:${JSON.stringify(value)}`);
    }
  }

  // ArkTS has no object spread, so property maps need an explicit field-by-field copy.
  private cloneJsonObject(source: ShuYiShuJsonObject): ShuYiShuJsonObject {
    const clone: ShuYiShuJsonObject = {};
    if (source.screen !== undefined) {
      clone.screen = source.screen;
    }
    if (source.previous_screen !== undefined) {
      clone.previous_screen = source.previous_screen;
    }
    if (source.dwell_ms !== undefined) {
      clone.dwell_ms = source.dwell_ms;
    }
    if (source.name !== undefined) {
      clone.name = source.name;
    }
    if (source.feature !== undefined) {
      clone.feature = source.feature;
    }
    if (source.source !== undefined) {
      clone.source = source.source;
    }
    if (source.tab !== undefined) {
      clone.tab = source.tab;
    }
    if (source.surface !== undefined) {
      clone.surface = source.surface;
    }
    if (source.section !== undefined) {
      clone.section = source.section;
    }
    if (source.action !== undefined) {
      clone.action = source.action;
    }
    if (source.outcome !== undefined) {
      clone.outcome = source.outcome;
    }
    if (source.error_category !== undefined) {
      clone.error_category = source.error_category;
    }
    if (source.latency_ms !== undefined) {
      clone.latency_ms = source.latency_ms;
    }
    if (source.duration_ms !== undefined) {
      clone.duration_ms = source.duration_ms;
    }
    if (source.event_count !== undefined) {
      clone.event_count = source.event_count;
    }
    if (source.screen_count !== undefined) {
      clone.screen_count = source.screen_count;
    }
    if (source.last_screen !== undefined) {
      clone.last_screen = source.last_screen;
    }
    if (source.end_reason !== undefined) {
      clone.end_reason = source.end_reason;
    }
    return clone;
  }

  private async postBatchWithRetry(body: string): Promise<void> {
    let lastError: ShuYiShuIngestionError = new ShuYiShuIngestionError(0);

    for (let attempt: number = 0; attempt <= this.retryAttempts; attempt += 1) {
      try {
        const requestHeaders: ShuYiShuHeaders = { 'content-type': 'application/json' };
        const request: ShuYiShuTransportRequest = {
          url: this.buildEventsUrl(),
          headers: requestHeaders,
          body: body,
        };
        const response: ShuYiShuTransportResponse = await this.options.transport.postJson(request);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }

        const ingestionError: ShuYiShuIngestionError = new ShuYiShuIngestionError(response.statusCode);
        if (!ingestionError.isRetryable) {
          throw ingestionError;
        }
        lastError = ingestionError;
      } catch (error) {
        if (error instanceof ShuYiShuIngestionError && !error.isRetryable) {
          throw error;
        }
        lastError = error instanceof ShuYiShuIngestionError ? error : new ShuYiShuIngestionError(0);
      }

      if (attempt < this.retryAttempts) {
        await this.delay(this.retryBaseDelayMs * Math.pow(2, attempt));
      }
    }

    throw lastError;
  }

  private restore(events: ShuYiShuEvent[]): void {
    this.queue = [...events, ...this.queue].slice(0, this.maxQueueSize);
    this.persistQueue();
  }

  private loadQueue(): ShuYiShuEvent[] {
    const storage: ShuYiShuStorage | undefined = this.options.storage;
    if (storage === undefined) {
      return [];
    }

    const raw: string | undefined = storage.getString(QUEUE_STORAGE_KEY);
    if (raw === undefined || raw.length === 0) {
      return [];
    }

    try {
      const parsed: ShuYiShuEvent[] = JSON.parse(raw) as ShuYiShuEvent[];
      return Array.isArray(parsed) ? parsed.slice(-this.maxQueueSize) : [];
    } catch (_) {
      storage.setString(QUEUE_STORAGE_KEY, '[]');
      return [];
    }
  }

  private persistQueue(): void {
    const storage: ShuYiShuStorage | undefined = this.options.storage;
    if (storage === undefined) {
      return;
    }

    storage.setString(QUEUE_STORAGE_KEY, JSON.stringify(this.queue));
  }

  private resolveAppContext(
    provided: ShuYiShuAppContext | undefined,
    appVersion: string,
    storage: ShuYiShuStorage | undefined,
  ): ShuYiShuAppContext | undefined {
    if (storage === undefined) {
      return provided;
    }

    const currentNow: Date = this.now();
    const storedFirstOpen: string | undefined = storage.getString(FIRST_OPEN_STORAGE_KEY);
    const parsedFirstMs: number = storedFirstOpen !== undefined ? Date.parse(storedFirstOpen) : NaN;
    const isFirstLaunch: boolean = Number.isNaN(parsedFirstMs);
    const firstOpenIso: string = isFirstLaunch ? currentNow.toISOString() : storedFirstOpen as string;
    if (isFirstLaunch) {
      storage.setString(FIRST_OPEN_STORAGE_KEY, firstOpenIso);
    }

    const firstMs: number = isFirstLaunch ? currentNow.getTime() : parsedFirstMs;
    const installAgeDays: number = Math.max(0, Math.floor((currentNow.getTime() - firstMs) / 86_400_000));
    const previousVersion: string | undefined = storage.getString(LAST_APP_VERSION_STORAGE_KEY);
    if (previousVersion === undefined || previousVersion !== appVersion) {
      storage.setString(LAST_APP_VERSION_STORAGE_KEY, appVersion);
    }

    const merged: ShuYiShuAppContext = {
      first_open_at: provided?.first_open_at ?? firstOpenIso,
      is_first_launch: provided?.is_first_launch ?? isFirstLaunch,
      install_age_days: provided?.install_age_days ?? installAgeDays,
    };
    if (provided?.build_mode !== undefined) {
      merged.build_mode = provided.build_mode;
    }
    if (provided?.distribution !== undefined) {
      merged.distribution = provided.distribution;
    }
    if (provided?.previous_app_version !== undefined) {
      merged.previous_app_version = provided.previous_app_version;
    } else if (previousVersion !== undefined && previousVersion.length > 0 && previousVersion !== appVersion) {
      merged.previous_app_version = previousVersion;
    }
    return merged;
  }

  private normalizeCountry(country: string | undefined): string | undefined {
    if (country === undefined) {
      return undefined;
    }
    const trimmed: string = country.trim().toUpperCase();
    return trimmed.length === 2 ? trimmed : undefined;
  }

  private buildEventsUrl(): string {
    const baseUrl: string = this.options.baseUrl.replace(/\/$/, '');
    return `${baseUrl}/api/events`;
  }
}
