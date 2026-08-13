import { describe, expect, it } from '@ohos/hypium';
import { validatedAuxiliaryRuleText } from '../main/ets/services/AdsBlockService';

export default function adsBlockServiceTest(): void {
  describe('AdsBlockService runtime rule scope', (): void => {
    it('accepts the small app supplement used by the auxiliary engine', 0, (): void => {
      const supplement: string = '||supplement.example^';

      expect(validatedAuxiliaryRuleText(supplement)).assertEqual(supplement);
    });

    it('rejects an oversized supplement before synchronous compilation', 0, (): void => {
      const oversized: string = 'x'.repeat(128 * 1024 + 1);

      expect(validatedAuxiliaryRuleText(oversized)).assertEqual('');
    });
  });
}
