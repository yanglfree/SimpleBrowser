import { common } from '@kit.AbilityKit'

export const IAP_PAYWALL_TOO_FREQUENT_ERROR = 'IAP_TOO_FREQUENT_REQUEST'
export const IAP_PAYWALL_PAYMENT_PENDING_ERROR = 'IAP_PAYMENT_PENDING'

export enum IapPaywallPlan {
  MONTHLY = 'monthly',
  YEARLY = 'yearly',
  LIFETIME = 'lifetime'
}

export enum IapPaywallProductSource {
  LIVE_STORE = 'live_store',
  FALLBACK = 'fallback'
}

export interface IapPaywallProductLoadResult {
  products: IapPaywallProduct[]
  source: IapPaywallProductSource
}

export interface IapPaywallComparisonRow {
  label: ResourceStr
  vipValue: ResourceStr
  freeValue: ResourceStr
}

export interface IapPaywallProduct {
  productId: string
  plan: IapPaywallPlan
  priceLabel: string
  originalPriceLabel: string
  periodLabel: string
  discountLabel: string
  promoLabel: string
  source: IapPaywallProductSource
  storePrice?: string
  title?: ResourceStr
  hintText?: ResourceStr
  ctaFormat?: string
  dailyValueLabel?: ResourceStr
}

export interface IapPaywallBenefit {
  icon: string
  title: ResourceStr
  description?: ResourceStr
}

export interface IapPaywallMetric {
  value: ResourceStr
  label: ResourceStr
}

export interface IapPaywallTheme {
  bodyBackground: ResourceColor
  bodyBorder: ResourceColor
  panelBackground: ResourceColor
  buttonNormal: ResourceColor
  buttonText: ResourceColor
  buttonTextActive: ResourceColor
  accentColor: ResourceColor
  titleText: ResourceColor
  // 以下为可选的面板/高亮 token（用于让卡片底随明暗主题翻转，避免深色主题下浅底压浅字）。
  // 不传时回退到组件内置的浅色默认值，保持向后兼容。
  cardBackground?: ResourceColor       // 主卡片/套餐卡/协议框底（浅色主题=白）
  cardBackgroundAlt?: ResourceColor    // 次级行/指标格/禁用按钮底（浅色主题=浅灰）
  highlightSurface?: ResourceColor     // 暖色高亮底：hero/选中套餐/提示/试用（浅色主题=奶油）
  highlightBorder?: ResourceColor      // 暖色高亮边框
}

export interface IapPaywallCopy {
  notLoggedLabel?: ResourceStr
  notMemberLabel?: ResourceStr
  // 套餐区标题（不传时回退到 offerTitle，保持旧接入方观感）
  planSectionTitle?: ResourceStr
  // 权益区标题（不传时回退到 offerTitle）
  benefitsTitle?: ResourceStr
  trialFreeLabel?: ResourceStr
  trialFreeHint?: ResourceStr
  trialPeriodLabel?: ResourceStr
  legalFooter?: ResourceStr
  comparisonTitle?: ResourceStr
  comparisonBenefitHeader?: ResourceStr
  comparisonVipHeader?: ResourceStr
  comparisonFreeHeader?: ResourceStr
  membershipLabel: ResourceStr
  heroTitleSuffix: ResourceStr
  heroSubtitle: ResourceStr
  offerTitle: ResourceStr
  offerSubtitle: ResourceStr
  monthlyPlanTitle: ResourceStr
  yearlyPlanTitle: ResourceStr
  lifetimePlanTitle: ResourceStr
  monthlyHint: ResourceStr
  yearlyHint: ResourceStr
  lifetimeHint: ResourceStr
  selectedSubscriptionNotice: ResourceStr
  selectedLifetimeNotice: ResourceStr
  autoRenewAgreePrefix: ResourceStr
  autoRenewAgreementLink: ResourceStr
  autoRenewAgreeSuffix: ResourceStr
  purchaseTermsAgreePrefix: ResourceStr
  purchaseTermsAgreeSuffix: ResourceStr
  subscriptionAutoRenewHint: ResourceStr
  purchaseAgreePrefix: ResourceStr
  purchaseAgreeAnd: ResourceStr
  privacyPolicy: ResourceStr
  userAgreement: ResourceStr
  supportEmailLabel: ResourceStr
  agreeTermsToContinue: ResourceStr
  subscribeNow: ResourceStr
  purchaseNow: ResourceStr
  purchasing: ResourceStr
  restorePurchase: ResourceStr
  manageSubscription: ResourceStr
  startPlaying: ResourceStr
  proActivatedTitle: ResourceStr
  memberExpiresHint: ResourceStr
  purchaseTermsRequired: ResourceStr
  purchaseCoolingDown: ResourceStr
  purchaseTooFrequent: ResourceStr
  purchaseRetryLater: ResourceStr
  iapEnvWarning: ResourceStr
  iapRetry: ResourceStr
  iapEnvErrorToast: ResourceStr
  iapEnvRetryFailed: ResourceStr
  iapEnvReady: ResourceStr
  purchaseSuccessToast: ResourceStr
  restoreSuccessToast: ResourceStr
  restoreEmptyToast: ResourceStr
  purchasePendingToast?: ResourceStr
  purchaseLaunchFailedPrefix: ResourceStr
}

export interface IapPaywallConfig {
  appName: ResourceStr
  proName: ResourceStr
  supportEmail: string
  termsUrl: string
  privacyUrl: string
  subscriptionManageErrorCode?: string
  defaultSelectedPlan: IapPaywallPlan
  defaultProducts: IapPaywallProduct[]
  metrics: IapPaywallMetric[]
  benefits: IapPaywallBenefit[]
  comparisonRows?: IapPaywallComparisonRow[]
  copy: IapPaywallCopy
}

export interface IapPaywallPurchaseAdapter {
  checkEnvironment(context: common.UIAbilityContext): Promise<boolean>
  queryProducts(context: common.UIAbilityContext): Promise<IapPaywallProductLoadResult>
  purchase(context: common.UIAbilityContext, product: IapPaywallProduct): Promise<boolean>
  restorePurchases(context: common.UIAbilityContext): Promise<boolean>
  manageSubscriptions(context: common.UIAbilityContext): Promise<void>
}

export class NoopPaywallPurchaseAdapter implements IapPaywallPurchaseAdapter {
  async checkEnvironment(_context: common.UIAbilityContext): Promise<boolean> {
    return false
  }

  async queryProducts(_context: common.UIAbilityContext): Promise<IapPaywallProductLoadResult> {
    return { products: [], source: IapPaywallProductSource.FALLBACK }
  }

  async purchase(_context: common.UIAbilityContext, _product: IapPaywallProduct): Promise<boolean> {
    return false
  }

  async restorePurchases(_context: common.UIAbilityContext): Promise<boolean> {
    return false
  }

  async manageSubscriptions(_context: common.UIAbilityContext): Promise<void> {}
}
