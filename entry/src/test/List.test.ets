import browserKernelServiceTest from './BrowserKernelService.test';
import browserViewModelTest from './BrowserViewModel.test';
import cosmeticFilterServiceTest from './CosmeticFilterService.test';
import ruleEngineTest from './RuleEngine.test';

export default function testsuite(): void {
  browserKernelServiceTest();
  browserViewModelTest();
  cosmeticFilterServiceTest();
  ruleEngineTest();
}
