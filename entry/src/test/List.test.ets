import browserKernelServiceTest from './BrowserKernelService.test';
import ruleEngineTest from './RuleEngine.test';

export default function testsuite(): void {
  browserKernelServiceTest();
  ruleEngineTest();
}
