import { errorManager } from '@kit.AbilityKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { Logger } from '../utils/Logger';
import {
  ReaderExtractionReport,
  ReaderExtractionBuckets,
  readerExtractionBuckets
} from '../models/ReaderExtractionModels';
import { allowsTelemetryWrite } from './TelemetryPolicy';

const TAG: string = 'TelemetryService';
const EVENT_DOMAIN: string = 'dolphin_browser';

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

/**
 * Privacy-friendly telemetry. Two hard rules:
 *
 * 1. Nothing leaves the device — events go through hiAppEvent, which the user
 *    can inspect or clear with the system's app-event tooling.
 * 2. No personal data. Page locations are omitted, and crash payloads carry
 *    only the exception category and name.
 * 3. A private tab suppresses every write, including coarse action events.
 */
export class TelemetryService {
  private static registered: boolean = false;
  private static enabled: boolean = false;
  private static privateContext: boolean = false;
  private static consentResolved: boolean = false;
  private static pendingStartupMs: number | undefined = undefined;

  /** Set from the privacy settings; off disables every write immediately. */
  static setEnabled(enabled: boolean): void {
    TelemetryService.enabled = enabled;
    TelemetryService.consentResolved = true;
    const pendingStartupMs: number | undefined = TelemetryService.pendingStartupMs;
    TelemetryService.pendingStartupMs = undefined;
    if (enabled && pendingStartupMs !== undefined) {
      const payload: StartupPayload = { duration_ms: TelemetryService.clamp(pendingStartupMs) };
      TelemetryService.writeEvent('startup', payload);
    }
    Logger.info(TAG, `Telemetry ${enabled ? 'enabled' : 'disabled'}`);
  }

  /** Called whenever the focused tab changes. Private browsing is a hard stop. */
  static setPrivateContext(privateContext: boolean): void {
    TelemetryService.privateContext = privateContext;
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
    const payload: StartupPayload = { duration_ms: TelemetryService.clamp(ms) };
    TelemetryService.writeEvent('startup', payload);
  }

  /** Records page-load duration without any page location. */
  static recordPageLoad(ms: number): void {
    if (ms < 0) {
      return;
    }
    const payload: PageLoadPayload = {
      duration_ms: TelemetryService.clamp(ms)
    };
    TelemetryService.writeEvent('page_load', payload);
  }

  /** Tab memory pressure downgrade, e.g. the app reclaimed background tabs. */
  static recordMemoryPressure(level: number): void {
    const payload: MemoryPayload = { level: level };
    TelemetryService.writeEvent('memory_pressure', payload);
  }

  /** Records only coarse quality metrics, never a page location or article content. */
  static reportReaderExtraction(report: ReaderExtractionReport): void {
    const buckets: ReaderExtractionBuckets = readerExtractionBuckets(report);
    const payload: ReaderPayload = {
      result: report.result,
      strategy: report.strategy,
      candidate_chars: buckets.candidateChars,
      output_ratio: buckets.outputRatio,
      paragraphs: buckets.paragraphs,
      image_count: Math.min(1000, Math.max(0, report.imageCount)),
      duration_ms: TelemetryService.clamp(report.durationMs)
    };
    TelemetryService.writeEvent('reader_extraction', payload);
  }

  static reportCrash(name: string, error: Error): void {
    const payload: CrashPayload = {
      kind: name,
      name: error.name ?? 'Error'
    };
    TelemetryService.writeEvent('crash', payload);
  }

  /** Menu/quick-action invocation; feeds the usage-ranking design without PII. */
  static reportActionUsage(key: string): void {
    if (key.length === 0) {
      return;
    }
    const payload: ActionUsagePayload = { action: TelemetryService.trim(key, 40) };
    TelemetryService.writeEvent('action_usage', payload);
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
