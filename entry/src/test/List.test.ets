import browserKernelServiceTest from './BrowserKernelService.test';
import cosmeticFilterServiceTest from './CosmeticFilterService.test';
import ruleEngineTest from './RuleEngine.test';

export default function testsuite(): void {
  browserKernelServiceTest();
  cosmeticFilterServiceTest();
  ruleEngineTest();
}
