import { describe, expect, it } from '@ohos/hypium'
import {
  defaultPaywallSelection,
  selectPaywallProduct,
  sanitizePaywallProducts
} from '../main/ets/models/IapPaywallSelection'
import { IapPaywallPlan, IapPaywallProductSource, IapPaywallProduct } from '../main/ets/models/IapPaywallModels'

const products: IapPaywallProduct[] = [
  {
    productId: 'example.pro.monthly', plan: IapPaywallPlan.MONTHLY, priceLabel: '¥30',
    originalPriceLabel: '', periodLabel: '月', discountLabel: '', promoLabel: '',
    source: IapPaywallProductSource.LIVE_STORE
  },
  {
    productId: 'example.pro.yearly', plan: IapPaywallPlan.YEARLY, priceLabel: '¥198',
    originalPriceLabel: '', periodLabel: '年', discountLabel: '', promoLabel: '',
    source: IapPaywallProductSource.LIVE_STORE
  },
  {
    productId: 'example.pro.lifetime', plan: IapPaywallPlan.LIFETIME, priceLabel: '¥588',
    originalPriceLabel: '', periodLabel: '永久', discountLabel: '', promoLabel: '',
    source: IapPaywallProductSource.LIVE_STORE
  }
]

export default function paywallSelectionTest() {
  describe('IapPaywallSelection', () => {
    it('defaults to yearly without trial', 0, () => {
      const selection = defaultPaywallSelection(products)
      expect(selection?.plan).assertEqual(IapPaywallPlan.YEARLY)
      expect(selection?.isTrial).assertEqual(false)
    })
    it('switches monthly and lifetime and supports explicit trial', 0, () => {
      expect(selectPaywallProduct(products, IapPaywallPlan.MONTHLY)?.plan).assertEqual(IapPaywallPlan.MONTHLY)
      expect(selectPaywallProduct(products, IapPaywallPlan.LIFETIME)?.plan).assertEqual(IapPaywallPlan.LIFETIME)
      expect(selectPaywallProduct(products, IapPaywallPlan.YEARLY, true)?.isTrial).assertEqual(true)
    })
    it('falls back to yearly for invalid selection', 0, () => {
      expect(selectPaywallProduct(products, 'invalid' as IapPaywallPlan)?.plan).assertEqual(IapPaywallPlan.YEARLY)
    })
    it('rejects blank and duplicate products without assuming app-specific ids', 0, () => {
      const invalid: IapPaywallProduct = {
        productId: ' ', plan: IapPaywallPlan.MONTHLY, priceLabel: '¥1', originalPriceLabel: '',
        periodLabel: '月', discountLabel: '', promoLabel: '', source: IapPaywallProductSource.LIVE_STORE
      }
      expect(sanitizePaywallProducts([invalid, products[1], products[1]]).length).assertEqual(1)
    })
    it('preserves canonical product id', 0, () => {
      const selection = defaultPaywallSelection(products)
      expect(selection?.kind).assertEqual('paid')
      if (selection?.kind === 'paid') expect(selection.product.productId).assertEqual('example.pro.yearly')
    })
    it('fails closed for empty price', 0, () => {
      const empty: IapPaywallProduct = {
        productId: 'example.pro.yearly', plan: IapPaywallPlan.YEARLY, priceLabel: '',
        originalPriceLabel: '', periodLabel: '年', discountLabel: '', promoLabel: '',
        source: IapPaywallProductSource.LIVE_STORE
      }
      expect(defaultPaywallSelection([empty])).assertUndefined()
    })
  })
}
