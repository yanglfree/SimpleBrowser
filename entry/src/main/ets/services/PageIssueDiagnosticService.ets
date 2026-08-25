import { LoadErrorKind } from '../models/BrowserModels';
import { BlockEngine, BlockEvent } from '../models/BlockEventModels';
import { SiteControl, SiteControlMode } from '../models/SiteControlModels';
import { BrowserWindowMetrics } from '../models/WindowMetrics';

export interface PageIssueDiagnostic {
  appVersion: string;
  layoutClass: number;
  widthVp: number;
  heightVp: number;
  loadError: LoadErrorKind;
  blockEventCount: number;
  ownRuleEventCount: number;
  systemRuleEventCount: number;
  siteOverrideCount: number;
}

/** Builds a URL-free, content-free snapshot that the user can inspect before copying. */
export class PageIssueDiagnosticService {
  static create(
    appVersion: string,
    metrics: BrowserWindowMetrics,
    loadError: LoadErrorKind,
    events: BlockEvent[],
    control: SiteControl
  ): PageIssueDiagnostic {
    return {
      appVersion: appVersion,
      layoutClass: metrics.layoutClass,
      widthVp: Math.round(metrics.widthVp),
      heightVp: Math.round(metrics.heightVp),
      loadError: loadError,
      blockEventCount: events.length,
      ownRuleEventCount: events.filter((event: BlockEvent): boolean =>
        event.engine === BlockEngine.OwnRuleEngine).length,
      systemRuleEventCount: events.filter((event: BlockEvent): boolean =>
        event.engine === BlockEngine.ArkWebSystemRules).length,
      siteOverrideCount: PageIssueDiagnosticService.overrideCount(control)
    };
  }

  static summary(diagnostic: PageIssueDiagnostic): string {
    return [
      `app_version=${diagnostic.appVersion}`,
      `layout_class=${diagnostic.layoutClass}`,
      `window_vp=${diagnostic.widthVp}x${diagnostic.heightVp}`,
      `load_error=${diagnostic.loadError}`,
      `block_events=${diagnostic.blockEventCount}`,
      `own_rule_events=${diagnostic.ownRuleEventCount}`,
      `system_rule_events=${diagnostic.systemRuleEventCount}`,
      `site_overrides=${diagnostic.siteOverrideCount}`
    ].join('\n');
  }

  private static overrideCount(control: SiteControl): number {
    const modes: SiteControlMode[] = [
      control.networkBlocking,
      control.trackerBlocking,
      control.cosmeticCleanup,
      control.autoReader,
      control.darkMode,
      control.desktopUserAgent
    ];
    return modes.filter((mode: SiteControlMode): boolean => mode !== SiteControlMode.Inherit).length;
  }
}
