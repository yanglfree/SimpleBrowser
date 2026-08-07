import { describe, expect, it } from '@ohos/hypium';
import { CosmeticFilterService } from '../main/ets/services/CosmeticFilterService';

export default function cosmeticFilterServiceTest(): void {
  describe('CosmeticFilterService selector matching', (): void => {
    it('applies generic and host rules while honoring exceptions', 0, (): void => {
      const service: CosmeticFilterService = CosmeticFilterService.compile([
        '##.generic-ad',
        'news.example##.sponsored',
        'news.example#@#.sponsored',
        'blog.example##.sponsored'
      ].join('\n'));

      const news: string[] = service.selectorsFor('https://news.example/article');
      expect(news.includes('.generic-ad')).assertTrue();
      expect(news.includes('.sponsored')).assertFalse();
      expect(service.selectorsFor('https://blog.example/post').includes('.sponsored')).assertTrue();
      expect(service.selectorsFor('https://other.example/post').includes('.sponsored')).assertFalse();
    });

    it('serves subdomains from the rules filed under their parent', 0, (): void => {
      const service: CosmeticFilterService = CosmeticFilterService.compile([
        'example.com##.promo',
        'other.com##.unrelated'
      ].join('\n'));

      expect(service.selectorsFor('https://m.news.example.com/a').includes('.promo')).assertTrue();
      expect(service.selectorsFor('https://example.com/a').includes('.promo')).assertTrue();
      expect(service.selectorsFor('https://notexample.com/a').includes('.promo')).assertFalse();
      expect(service.selectorsFor('https://example.com/a').includes('.unrelated')).assertFalse();
    });

    it('keeps child combinators, which are safe inside a stylesheet', 0, (): void => {
      const service: CosmeticFilterService = CosmeticFilterService.compile('##.wrap > .ad');

      expect(service.selectorsFor('https://example.com/').includes('.wrap > .ad')).assertTrue();
    });

    it('creates an early stylesheet injection script', 0, (): void => {
      const service: CosmeticFilterService = CosmeticFilterService.compile('##.ad-slot');
      const script: string = service.scriptFor('https://example.com');

      expect(script).assertContain('__minimalBrowserCosmeticRules');
      expect(script).assertContain('.ad-slot');
      expect(script).assertContain('display:none!important');
    });
  });
}
