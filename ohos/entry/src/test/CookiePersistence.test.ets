import { describe, expect, it } from '@ohos/hypium';
import { LEGACY_HUAWEI_HOST_COOKIES, legacyHuaweiCookieDeletion } from '../main/ets/services/CookiePersistence';

export default function cookiePersistenceTest(): void {
  describe('Cookie persistence', (): void => {
    it('expires legacy host shadows without targeting domain cookies', 0, (): void => {
      expect(LEGACY_HUAWEI_HOST_COOKIES.includes('developer_userinfo')).assertTrue();
      expect(LEGACY_HUAWEI_HOST_COOKIES.includes('authdata')).assertTrue();
      expect(legacyHuaweiCookieDeletion('developer_userinfo'))
        .assertEqual('developer_userinfo=; Max-Age=0; Path=/; Secure');
      expect(legacyHuaweiCookieDeletion('state').includes('Domain=')).assertFalse();
    });
  });
}
