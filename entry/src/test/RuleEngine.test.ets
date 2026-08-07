import { describe, expect, it } from '@ohos/hypium';
import { RuleEngine } from '../main/ets/services/RuleEngine';

export default function ruleEngineTest(): void {
  describe('RuleEngine EasyList matching', (): void => {
    it('matches domain, wildcard, and regex network rules', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile([
        '||ads.example.com^',
        '*/tracking/*',
        '/pixel[0-9]+/'
      ].join('\n'));

      expect(engine.shouldBlock({ url: 'https://ads.example.com/banner.js' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://cdn.example.com/tracking/pixel.gif' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://cdn.example.com/pixel123.gif' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://cdn.example.com/content.js' })).assertFalse();
    });

    it('reads a path rule as a substring, not as a regex literal', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile([
        '/in/track?data=',
        '/a/?ad='
      ].join('\n'));

      expect(engine.shouldBlock({ url: 'https://stats.example/in/track?data=1' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://cn.bing.com' })).assertFalse();
      expect(engine.shouldBlock({ url: 'https://example.com' })).assertFalse();
    });

    it('keeps options attached to a regex rule out of its pattern', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile('/banner[0-9]+/$script');

      expect(engine.shouldBlock({
        url: 'https://cdn.example/banner42.js',
        resourceType: 'script'
      })).assertTrue();
      expect(engine.shouldBlock({
        url: 'https://cdn.example/banner42.css',
        resourceType: 'stylesheet'
      })).assertFalse();
    });

    it('gives exception rules priority over blocking rules', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile([
        '||ads.example.com^',
        '@@||ads.example.com/allowed^'
      ].join('\n'));

      expect(engine.shouldBlock({ url: 'https://ads.example.com/banner.js' })).assertTrue();
      const result = engine.match({ url: 'https://ads.example.com/allowed/banner.js' });
      expect(result.blocked).assertFalse();
      expect(result.exception).assertTrue();
    });

    it('honors domain, resource type, and third-party options', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile(
        '||tracker.example^$script,third-party,domain=news.example|~private.news.example'
      );

      expect(engine.shouldBlock({
        url: 'https://tracker.example/app.js',
        pageUrl: 'https://news.example/article',
        resourceType: 'script'
      })).assertTrue();
      expect(engine.shouldBlock({
        url: 'https://tracker.example/app.css',
        pageUrl: 'https://news.example/article',
        resourceType: 'stylesheet'
      })).assertFalse();
      expect(engine.shouldBlock({
        url: 'https://tracker.example/app.js',
        pageUrl: 'https://private.news.example/article',
        resourceType: 'script'
      })).assertFalse();
    });

    it('anchors a domain rule to the host rather than the whole url', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile('||doubleclick.net^');

      expect(engine.shouldBlock({ url: 'https://ad.doubleclick.net/x.js' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://a.b.doubleclick.net/x.js' })).assertTrue();
      expect(engine.shouldBlock({ url: 'https://notdoubleclick.net/x.js' })).assertFalse();
      expect(engine.shouldBlock({
        url: 'https://safe.example/redir?u=/doubleclick.net/x'
      })).assertFalse();
    });

    it('drops rules whose options do not mean "block this request"', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile([
        '||pop.example^$popup',
        '||param.example^$removeparam=utm_source',
        '||csp.example^$csp=script-src \'self\'',
        '||future.example^$totally-unknown-option',
        '||kept.example^$important,third-party'
      ].join('\n'));

      expect(engine.shouldBlock({ url: 'https://pop.example/page' })).assertFalse();
      expect(engine.shouldBlock({ url: 'https://param.example/a?utm_source=x' })).assertFalse();
      expect(engine.shouldBlock({ url: 'https://csp.example/a.js' })).assertFalse();
      expect(engine.shouldBlock({ url: 'https://future.example/a.js' })).assertFalse();
      expect(engine.shouldBlock({
        url: 'https://kept.example/a.js',
        pageUrl: 'https://news.example/article'
      })).assertTrue();
    });

    it('accepts uBlock shorthands for resource types', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile('||api.example^$xhr,3p');

      expect(engine.shouldBlock({
        url: 'https://api.example/data.json',
        pageUrl: 'https://news.example/article',
        resourceType: 'xmlhttprequest'
      })).assertTrue();
      expect(engine.shouldBlock({
        url: 'https://api.example/main.js',
        pageUrl: 'https://news.example/article',
        resourceType: 'script'
      })).assertFalse();
    });

    it('blocks an ad SDK a site vendors under its own asset domain', 0, (): void => {
      // MSN loads the Xandr SDK from its own host, which is how its feed ads
      // survive EasyList's ||adsdk.microsoft.com^.
      const engine: RuleEngine = RuleEngine.compile('||assets.msn.com^*/thirdparty/adsdk/');

      expect(engine.shouldBlock({
        url: 'https://assets.msn.com/staticsb/statics/latest/js/thirdparty/adsdk/ast/1.10.80/ast.js',
        pageUrl: 'https://www.msn.cn/zh-cn/feed',
        resourceType: 'script'
      })).assertTrue();
      // The same host serves the site's own code, which must keep loading.
      expect(engine.shouldBlock({
        url: 'https://assets.msn.com/staticsb/statics/latest/js/main.js',
        pageUrl: 'https://www.msn.cn/zh-cn/feed',
        resourceType: 'script'
      })).assertFalse();
      expect(engine.shouldBlock({
        url: 'https://assets.msn.com/staticsb/statics/latest/fluent-icons/search_24_regular.svg',
        pageUrl: 'https://www.msn.cn/zh-cn/feed',
        resourceType: 'image'
      })).assertFalse();
    });

    it('disables a rule paired with the AdGuard badfilter option', 0, (): void => {
      const engine: RuleEngine = RuleEngine.compile([
        '||disabled.example^',
        '||disabled.example^$badfilter',
        '||enabled.example^'
      ].join('\n'));

      expect(engine.shouldBlock({ url: 'https://disabled.example/ad.js' })).assertFalse();
      expect(engine.shouldBlock({ url: 'https://enabled.example/ad.js' })).assertTrue();
    });
  });
}
