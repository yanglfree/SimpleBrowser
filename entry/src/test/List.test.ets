import browserKernelServiceTest from './BrowserKernelService.test';
import browserInteractionTest from './BrowserInteraction.test';
import browserSettingsTest from './BrowserSettings.test';
import browserViewModelTest from './BrowserViewModel.test';
import cosmeticFilterServiceTest from './CosmeticFilterService.test';
import downloadPolicyTest from './DownloadPolicy.test';
import ruleEngineTest from './RuleEngine.test';
import windowMetricsTest from './WindowMetrics.test';
import browserShortcutTest from './BrowserShortcut.test';
import tabOverviewLayoutTest from './TabOverviewLayout.test';

export default function testsuite(): void {
  browserKernelServiceTest();
  browserInteractionTest();
  browserSettingsTest();
  browserViewModelTest();
  cosmeticFilterServiceTest();
  downloadPolicyTest();
  ruleEngineTest();
  windowMetricsTest();
  browserShortcutTest();
  tabOverviewLayoutTest();
}
