import { describe, expect, it } from '@ohos/hypium';
import { readerApplyScript } from '../main/ets/constants/AppConstants';

export default function readerModeRegressionTest(): void {
  describe('Reader mode regressions', (): void => {
    it('selects the complete WeChat article body before the capped paragraph fallback', 0, (): void => {
      const script: string = readerApplyScript(17, 205, '#fff', '#111', '#111', '#06f');

      expect(script.includes('#js_content, .rich_media_content')).assertTrue();
      expect(script.indexOf('#js_content, .rich_media_content') < script.indexOf('fallbackLength >= 1600'))
        .assertTrue();
    });
  });
}
