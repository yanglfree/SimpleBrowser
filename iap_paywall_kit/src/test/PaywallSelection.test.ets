import { describe, expect, it } from '@ohos/hypium'
import {
  defaultPaywallSelection,
  selectPaywallProduct,
  sanitizePaywallProducts,
  getPaywallItemKey
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
    it('generates selection-aware keys so ForEach re-renders checkmark on plan change', 0, () => {
      const monthlyProduct = products[0]
      const yearlyProduct = products[1]
      const lifetimeProduct = products[2]

      // Initially yearly is selected
      const yearlyKeyInitial = getPaywallItemKey(yearlyProduct, IapPaywallPlan.YEARLY, false)
      const monthlyKeyInitial = getPaywallItemKey(monthlyProduct, IapPaywallPlan.YEARLY, false)
      expect(yearlyKeyInitial).assertEqual('example.pro.yearly_1_¥198_')
      expect(monthlyKeyInitial).assertEqual('example.pro.monthly_0_¥30_')

      // Switch selection to monthly
      const yearlyKeyAfterSwitch = getPaywallItemKey(yearlyProduct, IapPaywallPlan.MONTHLY, false)
      const monthlyKeyAfterSwitch = getPaywallItemKey(monthlyProduct, IapPaywallPlan.MONTHLY, false)
      expect(yearlyKeyAfterSwitch).assertEqual('example.pro.yearly_0_¥198_')
      expect(monthlyKeyAfterSwitch).assertEqual('example.pro.monthly_1_¥30_')
      expect(yearlyKeyInitial !== yearlyKeyAfterSwitch).assertTrue()
      expect(monthlyKeyInitial !== monthlyKeyAfterSwitch).assertTrue()

      // Switch selection to lifetime
      const lifetimeKeySelected = getPaywallItemKey(lifetimeProduct, IapPaywallPlan.LIFETIME, false)
      expect(lifetimeKeySelected).assertEqual('example.pro.lifetime_1_¥588_')

      // When trial is selected, paid plans are marked unselected
      const yearlyKeyTrial = getPaywallItemKey(yearlyProduct, IapPaywallPlan.YEARLY, true)
      expect(yearlyKeyTrial).assertEqual('example.pro.yearly_0_¥198_')
    })
  })
}
