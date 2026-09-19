import { describe, expect, it } from '@ohos/hypium';
import {
  cookieFlushUrls,
  deviceDropsSessionCookies,
  isHttpsUrl,
  isPoisonedEphemeralCookie,
  isPromotableSessionCookie,
  originOf,
  parseCookiePairs,
  persistentDeleteCookie,
  persistentSetCookie,
  SESSION_COOKIE_MAX_AGE_SEC
} from '../main/ets/services/CookiePersistence';

export default function cookiePersistenceTest(): void {
  describe('Cookie persistence', (): void => {
    it('promotes session cookies only on devices that drop them', 0, (): void => {
      expect(deviceDropsSessionCookies('tablet')).assertTrue();
      expect(deviceDropsSessionCookies('2in1')).assertTrue();
      expect(deviceDropsSessionCookies('pc')).assertTrue();
      expect(deviceDropsSessionCookies('phone')).assertFalse();
      expect(deviceDropsSessionCookies('')).assertFalse();
    });

    it('collects unique http origins from tabs before history', 0, (): void => {
      const urls: string[] = cookieFlushUrls(
        [
          'https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/',
          'browser://home',
          'https://developer.huawei.com/other'
        ],
        [
          'https://id1.cloud.huawei.com/login',
          'https://developer.huawei.com/consumer/cn/'
        ],
        8
      );
      expect(urls.length).assertEqual(2);
      expect(urls[0]).assertEqual('https://developer.huawei.com/');
      expect(urls[1]).assertEqual('https://id1.cloud.huawei.com/');
    });

    it('parses cookie pairs and skips warm-up tokens and ephemeral oauth nonces', 0, (): void => {
      const pairs = parseCookiePairs('session=abc; dpkeep=1; state=nonce123; urlBeforeLogin=/home; code=auth456; hwssot=token; empty');
      expect(pairs.length).assertEqual(2);
      expect(pairs[0].name).assertEqual('session');
      expect(pairs[0].value).assertEqual('abc');
      expect(pairs[1].name).assertEqual('hwssot');
      expect(pairs[1].value).assertEqual('token');
      expect(isPromotableSessionCookie('state')).assertFalse();
      expect(isPromotableSessionCookie('urlBeforeLogin')).assertFalse();
      expect(isPromotableSessionCookie('oauth_token')).assertFalse();
      expect(isPromotableSessionCookie('session')).assertTrue();
      expect(isPoisonedEphemeralCookie('state')).assertTrue();
      expect(isPoisonedEphemeralCookie('urlBeforeLogin')).assertTrue();
    });

    it('writes a persistent Set-Cookie line with Secure only on https', 0, (): void => {
      expect(originOf('https://example.com/path?q=1#/')).assertEqual('https://example.com');
      expect(isHttpsUrl('https://example.com')).assertTrue();
      expect(isHttpsUrl('http://example.com')).assertFalse();
      expect(persistentSetCookie('sid', '1', true))
        .assertEqual(`sid=1; Max-Age=${SESSION_COOKIE_MAX_AGE_SEC}; Path=/; Secure`);
      expect(persistentSetCookie('sid', '1', false))
        .assertEqual(`sid=1; Max-Age=${SESSION_COOKIE_MAX_AGE_SEC}; Path=/`);
      expect(persistentDeleteCookie('state', true))
        .assertEqual('state=; Max-Age=0; Path=/; Secure');
      expect(persistentDeleteCookie('state', false))
        .assertEqual('state=; Max-Age=0; Path=/');
    });
  });
}
