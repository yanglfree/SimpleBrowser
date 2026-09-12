import { describe, expect, it } from '@ohos/hypium';
import { LoadErrorKind } from '../main/ets/models/BrowserModels';
import { BlockCategory, BlockEngine, createBlockEvent } from '../main/ets/models/BlockEventModels';
import { defaultSiteControl, SiteControlMode } from '../main/ets/models/SiteControlModels';
import { BrowserWindowMode, createWindowMetrics } from '../main/ets/models/WindowMetrics';
import { PageIssueDiagnosticService } from '../main/ets/services/PageIssueDiagnosticService';

export default function pageIssueDiagnosticServiceTest(): void {
  describe('Page issue diagnostic service', (): void => {
    it('summarizes local runtime state without accepting page URLs or content', 0, (): void => {
      const control = defaultSiteControl('private.example');
      control.autoReader = SiteControlMode.Enabled;
      const diagnostic = PageIssueDiagnosticService.create(
        '1.0.0',
        createWindowMetrics(840, 1200, BrowserWindowMode.Split),
        LoadErrorKind.Offline,
        [createBlockEvent('tab-1', 'https://private.example/path', BlockCategory.Tracker,
          BlockEngine.ArkWebSystemRules)],
        control
      );
      const summary: string = PageIssueDiagnosticService.summary(diagnostic);

      expect(summary).assertContain('block_events=1');
      expect(summary).assertContain('site_overrides=1');
      expect(summary.includes('private.example')).assertFalse();
      expect(summary.includes('/path')).assertFalse();
    });
  });
}
