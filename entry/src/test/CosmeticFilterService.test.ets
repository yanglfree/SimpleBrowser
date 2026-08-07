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

    it('hides a custom element that reserves an ad slot', 0, (): void => {
      // MSN's feed places each ad as its own element in the light DOM, and the
      // .cn portal shares nothing with the msn.com rules EasyList carries.
      const service: CosmeticFilterService = CosmeticFilterService.compile([
        'msn.cn,msn.com##csm-native-ad-card',
        'msn.cn,msn.com##csm-card[card-type="nativead"]'
      ].join('\n'));

      const selectors: string[] = service.selectorsFor('https://www.msn.cn/zh-cn/feed');
      expect(selectors.includes('csm-native-ad-card')).assertTrue();
      expect(selectors.includes('csm-card[card-type="nativead"]')).assertTrue();
      expect(service.selectorsFor('https://www.msn.com/en-us/news')
        .includes('csm-native-ad-card')).assertTrue();
      expect(service.selectorsFor('https://example.com/')
        .includes('csm-native-ad-card')).assertFalse();
    });

    it('creates an early stylesheet injection script', 0, (): void => {
      const service: CosmeticFilterService = CosmeticFilterService.compile('##.ad-slot');
      const script: string = service.scriptFor('https://example.com');

      expect(script).assertContain('__minimalBrowserCosmeticRules');
      expect(script).assertContain('.ad-slot');
      expect(script).assertContain('display:none!important');
    });

    it('keeps host rules ahead of generic ones', 0, (): void => {
      // Adding the Chinese subscriptions pushes the generic pool past the cap;
      // filling from that end would drop the rules written for the page.
      const lines: string[] = [];
      for (let index: number = 0; index < 40; index += 1) {
        lines.push(`##.generic-${index}`);
      }
      lines.push('news.example##.site-specific-ad');
      const service: CosmeticFilterService = CosmeticFilterService.compile(lines.join('\n'));

      const selectors: string[] = service.selectorsFor('https://news.example/article');
      expect(selectors[0]).assertEqual('.site-specific-ad');
      expect(selectors.includes('.generic-0')).assertTrue();
    });

    it('carries the stylesheet into shadow roots', 0, (): void => {
      // Component-built sites keep their ad slots several roots deep, where a
      // stylesheet in the document cannot reach them.
      const script: string = CosmeticFilterService.compile('##.ad-slot')
        .scriptFor('https://example.com');

      expect(script).assertContain('attachShadow');
      expect(script).assertContain('shadowRoot');
    });
  });
}
