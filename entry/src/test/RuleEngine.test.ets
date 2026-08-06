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

    it('restores matching behavior from the compiled cache shape', 0, (): void => {
      const source: string = '||cache.example^\n@@||cache.example/ok^';
      const engine: RuleEngine = RuleEngine.compile(source);
      const restored: RuleEngine | undefined = RuleEngine.fromCache(
        engine.serialize(RuleEngine.fingerprint(source))
      );

      expect(restored !== undefined).assertTrue();
      expect(restored?.shouldBlock({ url: 'https://cache.example/ad.js' })).assertTrue();
      expect(restored?.shouldBlock({ url: 'https://cache.example/ok/ad.js' })).assertFalse();
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
