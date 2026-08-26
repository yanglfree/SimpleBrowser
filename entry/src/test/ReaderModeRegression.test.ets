import { describe, expect, it } from '@ohos/hypium';
import { ARTICLE_CAPTURE_SCRIPT, readerApplyScript } from '../main/ets/constants/AppConstants';

export default function readerModeRegressionTest(): void {
  describe('Reader mode regressions', (): void => {
    it('wires reader rendering and offline capture to the same extraction core', 0, (): void => {
      const script: string = readerApplyScript(17, 205, '#fff', '#111', '#111', '#06f');

      expect(script.includes('window.__zhuoReaderExtract')).assertTrue();
      expect(ARTICLE_CAPTURE_SCRIPT.includes('window.__zhuoReaderExtract')).assertTrue();
      expect(script.includes('fallbackLength >= 1600')).assertFalse();
    });
  });
}
