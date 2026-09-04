import { IapPaywallPlan, IapPaywallProduct, IapPaywallProductSource } from './IapPaywallModels'

export function isValidPaywallProduct(product: IapPaywallProduct): boolean {
  return product.productId.trim().length > 0 && product.priceLabel.trim().length > 0
}

export function isPurchasablePaywallProduct(product: IapPaywallProduct): boolean {
  return product.source === IapPaywallProductSource.LIVE_STORE && isValidPaywallProduct(product)
}

export function sanitizePaywallProducts(products: IapPaywallProduct[]): IapPaywallProduct[] {
  const seen: string[] = []
  return products.filter((item: IapPaywallProduct) => {
    const valid = isValidPaywallProduct(item) && seen.indexOf(item.productId) < 0
    if (valid) seen.push(item.productId)
    return valid
  })
}

export type IapPaywallSelection = PaidPaywallSelection | TrialPaywallSelection

export interface PaidPaywallSelection {
  kind: 'paid'
  plan: IapPaywallPlan
  product: IapPaywallProduct
  isTrial: false
}

export interface TrialPaywallSelection {
  kind: 'trial'
  plan: IapPaywallPlan
  isTrial: true
}

export function selectPaywallProduct(
  products: IapPaywallProduct[],
  requestedPlan: IapPaywallPlan = IapPaywallPlan.YEARLY,
  isTrial: boolean = false
): IapPaywallSelection | undefined {
  const validProducts = sanitizePaywallProducts(products)
  if (validProducts.length === 0) return undefined
  const requested = validProducts.find((item: IapPaywallProduct) => item.plan === requestedPlan)
  const yearly = validProducts.find((item: IapPaywallProduct) => item.plan === IapPaywallPlan.YEARLY)
  const monthly = validProducts.find((item: IapPaywallProduct) => item.plan === IapPaywallPlan.MONTHLY)
  const lifetime = validProducts.find((item: IapPaywallProduct) => item.plan === IapPaywallPlan.LIFETIME)
  const product = requested || yearly || monthly || lifetime
  if (!product) return undefined
  if (isTrial) return { kind: 'trial', plan: product.plan, isTrial: true }
  return { kind: 'paid', plan: product.plan, product, isTrial: false }
}

export function defaultPaywallSelection(products: IapPaywallProduct[]): IapPaywallSelection | undefined {
  return selectPaywallProduct(products, IapPaywallPlan.YEARLY, false)
}

export function getPaywallItemKey(
  product: IapPaywallProduct,
  selectedPlan: IapPaywallPlan,
  isTrialSelected: boolean = false
): string {
  const isSelected = !isTrialSelected && product.plan === selectedPlan
  return `${product.productId}_${isSelected ? '1' : '0'}_${product.priceLabel}_${product.discountLabel}`
}
