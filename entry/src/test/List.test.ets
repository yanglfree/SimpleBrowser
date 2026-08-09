import browserKernelServiceTest from './BrowserKernelService.test';
import browserInteractionTest from './BrowserInteraction.test';
import browserViewModelTest from './BrowserViewModel.test';
import cosmeticFilterServiceTest from './CosmeticFilterService.test';
import ruleEngineTest from './RuleEngine.test';

export default function testsuite(): void {
  browserKernelServiceTest();
  browserInteractionTest();
  browserViewModelTest();
  cosmeticFilterServiceTest();
  ruleEngineTest();
}
