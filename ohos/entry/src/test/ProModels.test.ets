import { describe, expect, it } from '@ohos/hypium';

import {
  NON_CONSUMABLE_PRODUCT_TYPE,
  PRO_LIFETIME_PRODUCT_ID,
  PRO_MONTHLY_PRODUCT_ID,
  ProEntitlement,
  SUBSCRIPTION_PRODUCT_TYPE,
  isActiveProEntitlement,
  isKnownProProduct,
  productTypeForId
} from '../main/ets/models/ProModels';

function entitlement(active: boolean = true, scope: string = 'pro', expiresAt: number = 2_000): ProEntitlement {
  return {
    active: active,
    scope: scope,
    plan: null,
    productId: PRO_MONTHLY_PRODUCT_ID,
    expiresAt: expiresAt,
    source: 'server',
    verifiedAt: 1_000
  };
}

export default function proModelsTest(): void {
  describe('Pro models', (): void => {
    it('recognizes only the registered ZhuoBrowser products', 0, (): void => {
      expect(isKnownProProduct(PRO_MONTHLY_PRODUCT_ID)).assertTrue();
      expect(isKnownProProduct('com.example.unknown')).assertFalse();
    });

    it('maps lifetime and subscription product types', 0, (): void => {
      expect(productTypeForId(PRO_LIFETIME_PRODUCT_ID)).assertEqual(NON_CONSUMABLE_PRODUCT_TYPE);
      expect(productTypeForId(PRO_MONTHLY_PRODUCT_ID)).assertEqual(SUBSCRIPTION_PRODUCT_TYPE);
    });

    it('requires an active pro-scoped unexpired server entitlement', 0, (): void => {
      expect(isActiveProEntitlement(entitlement(), 1_500)).assertTrue();
      expect(isActiveProEntitlement(entitlement(false), 1_500)).assertFalse();
      expect(isActiveProEntitlement(entitlement(true, 'other'), 1_500)).assertFalse();
      expect(isActiveProEntitlement(entitlement(), 2_001)).assertFalse();
    });

    it('accepts a zero expiry only for lifetime-style active entitlements', 0, (): void => {
      expect(isActiveProEntitlement(entitlement(true, 'pro', 0), 9_999)).assertTrue();
    });
  });
}
