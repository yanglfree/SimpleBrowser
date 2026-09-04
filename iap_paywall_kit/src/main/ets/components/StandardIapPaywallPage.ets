import { common, OpenLinkOptions } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import hilog from '@ohos.hilog'
import {
  IAP_PAYWALL_TOO_FREQUENT_ERROR,
  IAP_PAYWALL_PAYMENT_PENDING_ERROR,
  IapPaywallBenefit,
  IapPaywallComparisonRow,
  IapPaywallConfig,
  IapPaywallMetric,
  IapPaywallPlan,
  IapPaywallProduct,
  IapPaywallProductSource,
  IapPaywallPurchaseAdapter,
  IapPaywallTheme,
  NoopPaywallPurchaseAdapter
} from '../models/IapPaywallModels'
import { getPaywallItemKey, isPurchasablePaywallProduct } from '../models/IapPaywallSelection'
import { PendingPurchaseRecovery, PurchaseRecoveryResult } from '../models/PendingPurchaseRecovery'

const TAG = 'StandardIapPaywallPage'

// ── 布局栅格（4vp 基数）──
// 页面只有一条内容轴：所有区块左右对齐到同一条 CONTENT_GUTTER 上，
// 超宽屏（Pad/折叠屏展开）用 CONTENT_MAX_WIDTH 收窄并居中，避免行长失控。
const CONTENT_MAX_WIDTH = 560
const CONTENT_GUTTER = 20
const CONTENT_TOP_PADDING = 44
const CONTENT_BOTTOM_PADDING = 32
const SECTION_SPACE = 20
const COMPACT_LAYOUT_WIDTH = 520
const CLOSE_BUTTON_SIZE = 36
const CLOSE_BUTTON_TOP = 52

const PLAN_CARD_HEIGHT = 136
const PLAN_ROW_HEIGHT = 78
const PLAN_TAG_SLOT_HEIGHT = 20
const PLAN_CARD_BORDER = 2
const COMPARISON_ROW_HEIGHT = 46
const PURCHASE_COOLDOWN_SECONDS = 2
const PURCHASE_THROTTLE_COOLDOWN_SECONDS = 5
const HERO_WARM_BACKGROUND = '#FFF7EA'
const HERO_WARM_ACCENT = '#F4E1C4'
const SELECTED_PLAN_BACKGROUND = '#FFF3DE'
const BENEFIT_ROW_BACKGROUND = '#F8FAFE'
const PLAN_CARD_BACKGROUND = '#FFFFFF'
const SOFT_AMBER_BORDER = '#EAD1A7'
const PAYWALL_CARD_SHADOW = '#18203324'

const DEFAULT_THEME: IapPaywallTheme = {
  bodyBackground: '#111318',
  bodyBorder: 'rgba(255,255,255,0.14)',
  panelBackground: '#1E2026',
  buttonNormal: '#2A2D35',
  buttonText: 'rgba(255,255,255,0.62)',
  buttonTextActive: '#FFFFFF',
  accentColor: '#FF9A4E',
  titleText: '#F8F4EF'
}

const DEFAULT_PRODUCTS: IapPaywallProduct[] = [
  {
    productId: 'monthly',
    plan: IapPaywallPlan.MONTHLY,
    priceLabel: '¥12',
    originalPriceLabel: '',
    periodLabel: '月',
    discountLabel: '',
    promoLabel: ''
    , source: IapPaywallProductSource.FALLBACK
  },
  {
    productId: 'yearly',
    plan: IapPaywallPlan.YEARLY,
    priceLabel: '¥68',
    originalPriceLabel: '',
    periodLabel: '年',
    discountLabel: '52%折扣',
    promoLabel: ''
    , source: IapPaywallProductSource.FALLBACK
  },
  {
    productId: 'lifetime',
    plan: IapPaywallPlan.LIFETIME,
    priceLabel: '¥99',
    originalPriceLabel: '¥128',
    periodLabel: '永久',
    discountLabel: '77%折扣',
    promoLabel: '限时特惠'
    , source: IapPaywallProductSource.FALLBACK
  }
]

const DEFAULT_CONFIG: IapPaywallConfig = {
  appName: 'App',
  proName: 'PRO',
  supportEmail: 'support@example.com',
  termsUrl: '',
  privacyUrl: '',
  defaultSelectedPlan: IapPaywallPlan.YEARLY,
  defaultProducts: DEFAULT_PRODUCTS,
  metrics: [
    { value: '8', label: '权益' },
    { value: '全部', label: '内容' },
    { value: '不限', label: '容量' }
  ],
  benefits: [
    { icon: '✨', title: '解锁全部 PRO 权益' },
    { icon: '📚', title: '持续更新高级内容' }
  ],
  copy: {
    membershipLabel: '会员中心',
    heroTitleSuffix: ' PRO',
    heroSubtitle: '解锁完整体验。',
    offerTitle: '完整专业套装',
    offerSubtitle: '把核心高级能力集中到一个会员里。',
    monthlyPlanTitle: '月度订阅',
    yearlyPlanTitle: '年度订阅',
    lifetimePlanTitle: '终身会员',
    monthlyHint: '按月计费',
    yearlyHint: '年度更划算',
    lifetimeHint: '一次购买永久使用',
    selectedSubscriptionNotice: '月会员与年会员均为自动续费订阅，到期后将自动续费；' +
      '可随时取消。',
    selectedLifetimeNotice: '终身会员为一次购买、永久解锁的非消耗型项目，购买后可恢复。',
    autoRenewAgreePrefix: '我已阅读并同意',
    autoRenewAgreementLink: '《自动续费服务协议》',
    autoRenewAgreeSuffix: '，到期自动续费，可随时取消',
    purchaseTermsAgreePrefix: '我已阅读并同意',
    purchaseTermsAgreeSuffix: '中的购买规则',
    subscriptionAutoRenewHint: '订阅到期前会自动续费，可随时在系统订阅管理中取消。',
    purchaseAgreePrefix: '购买即表示同意 ',
    purchaseAgreeAnd: ' 与 ',
    privacyPolicy: '隐私政策',
    userAgreement: '用户协议',
    supportEmailLabel: '客服邮箱：',
    agreeTermsToContinue: '同意协议后继续',
    subscribeNow: '立即订阅',
    purchaseNow: '立即购买',
    purchasing: '购买中...',
    restorePurchase: '恢复购买',
    manageSubscription: '管理订阅',
    startPlaying: '开始使用',
    proActivatedTitle: '已解锁 PRO 权益',
    memberExpiresHint: '会员有效期至',
    purchaseTermsRequired: '请先阅读并同意购买协议',
    purchaseCoolingDown: '支付处理中，请稍后再试',
    purchaseTooFrequent: '支付请求太频繁，请稍后再试',
    purchaseRetryLater: '请稍后',
    iapEnvWarning: '内购服务暂不可用，请稍后重试。',
    iapRetry: '重试',
    iapEnvErrorToast: '内购服务暂不可用，请稍后重试',
    iapEnvRetryFailed: '内购服务仍不可用',
    iapEnvReady: '内购服务已就绪',
    purchaseSuccessToast: '开通成功',
    restoreSuccessToast: '权益已恢复',
    restoreEmptyToast: '未找到有效的购买记录',
    purchasePendingToast: '支付已完成，权益同步中，请稍后查看',
    purchaseLaunchFailedPrefix: '支付唤起失败，请稍后再试'
  }
}

@Component
export struct StandardIapPaywallPage {
  theme: IapPaywallTheme = DEFAULT_THEME
  config: IapPaywallConfig = DEFAULT_CONFIG
  adapter: IapPaywallPurchaseAdapter = new NoopPaywallPurchaseAdapter()
  @Prop @Watch('onIsProChanged') isPro: boolean = false
  proStatusText: ResourceStr = ''
  proExpiresText: ResourceStr = ''
  // 免费试用（可选，默认关闭，向后兼容旧接入方）
  showTrialOption: boolean = false
  trialCtaLabel: ResourceStr = ''
  trialSubLabel: ResourceStr = ''
  trialSuccessToast: ResourceStr = ''
  onStartTrial: () => Promise<boolean> = async () => false
  onClose: () => void = () => {}
  onPaywallAppear: () => void = () => {}
  onPurchaseSucceeded: () => void = () => {}
  onRestoreSucceeded: () => void = () => {}

  @State private selectedPlan: IapPaywallPlan = IapPaywallPlan.YEARLY
  @State private products: IapPaywallProduct[] = DEFAULT_PRODUCTS
  @State private productSource: IapPaywallProductSource = IapPaywallProductSource.FALLBACK
  @State private isCompactLayout: boolean = false
  @State private isPurchasing: boolean = false
  @State private isStartingTrial: boolean = false
  @State private agreedPurchaseTerms: boolean = false
  @State private isEnvironmentReady: boolean = true
  @State private isLoadingProducts: boolean = false
  @State private animateOn: boolean = false
  @State private purchaseCooldownRemainingSec: number = 0
  @State private entitlementRestored: boolean = false
  @State private isTrialSelected: boolean = false

  private purchaseCooldownTimer: number = -1
  private pendingRecovery: PendingPurchaseRecovery = new PendingPurchaseRecovery()
  private isPaywallVisible: boolean = false

  aboutToAppear(): void {
    this.isPaywallVisible = true
    this.entitlementRestored = this.isPro
    this.onPaywallAppear()
    this.selectedPlan = this.config.defaultSelectedPlan
    this.products = this.config.defaultProducts
    this.loadProducts()
    this.isTrialSelected = false
    setTimeout(() => {
      animateTo({ duration: 500, curve: Curve.EaseOut }, () => {
        this.animateOn = true
      })
    }, 50)
  }

  aboutToDisappear(): void {
    this.isPaywallVisible = false
    this.clearPurchaseCooldownTimer()
    this.pendingRecovery.cancel()
  }

  // 面板/高亮底解析：优先用接入方传入的主题 token（可随明暗翻转），
  // 未提供时回退到组件内置浅色默认值，保证独立使用时观感不变。
  private resolveHighlightSurface(fallback: ResourceColor): ResourceColor {
    return this.theme.highlightSurface ?? fallback
  }

  private resolveHighlightBorder(fallback: ResourceColor): ResourceColor {
    return this.theme.highlightBorder ?? fallback
  }

  private resolveCardSurface(fallback: ResourceColor): ResourceColor {
    return this.theme.cardBackground ?? fallback
  }

  private resolveCardSurfaceAlt(fallback: ResourceColor): ResourceColor {
    return this.theme.cardBackgroundAlt ?? fallback
  }

  private async loadProducts(): Promise<void> {
    this.isLoadingProducts = true
    try {
      const context = getContext(this) as common.UIAbilityContext
      const envOk = await this.adapter.checkEnvironment(context)
      this.isEnvironmentReady = envOk
      if (!envOk) {
        hilog.error(0x0000, TAG, 'IAP environment check failed on load')
        return
      }
      const result = await this.adapter.queryProducts(context)
      this.productSource = result.source
      if (result.products.length > 0) {
        this.products = result.products
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load products error: ' + String(err))
      this.isEnvironmentReady = false
    } finally {
      this.isLoadingProducts = false
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        // Scroll 内容短于视口时默认竖直居中，会在 Pad 上把整页顶下去；
        // 用 .align(Alignment.Top) 把内容钉在顶部。
        Column() {
          Column({ space: SECTION_SPACE }) {
            this.Header()

            if (this.shouldShowProStatus()) {
              this.ProStatusView()
            } else {
              if (!this.isEnvironmentReady) {
                this.EnvironmentWarningBanner()
              }
              this.HeroSection()
              this.PlanSelector()
              this.SelectedPlanNotice()
              if (!this.isTrialSelected) {
                this.PurchaseTermsConsent()
              }
              this.PurchaseButton()
              this.BenefitsSection()
              this.ComparisonSection()
              this.FooterSection()
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: CONTENT_GUTTER,
            right: CONTENT_GUTTER,
            top: CONTENT_TOP_PADDING,
            bottom: CONTENT_BOTTOM_PADDING
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .onAreaChange((_oldArea, newArea) => {
        // Below 520vp, stack the paid options as full-width rows instead of squeezing columns.
        this.isCompactLayout = Number(newArea.width) < COMPACT_LAYOUT_WIDTH
      })
      .opacity(this.animateOn ? 1 : 0)
      .translate({ y: this.animateOn ? 0 : 30 })

      this.CloseButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.bodyBackground)
  }

  @Builder
  Header() {
    Row({ space: 12 }) {
      Row() {
        Text(this.config.proName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.accentColor)
          .maxLines(1)
      }
      .width(52)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveHighlightSurface(HERO_WARM_BACKGROUND))
      .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
      .borderRadius(26)

      Column({ space: 4 }) {
        Text(this.config.copy.membershipLabel)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 已开通时不能再说"未开通会员"，副标题跟随权益状态。
        Text(this.shouldShowProStatus()
          ? (this.proStatusText || this.config.proName)
          : (this.config.copy.notMemberLabel || this.config.proName))
          .fontSize(12)
          .fontColor(this.theme.buttonText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    // 右侧让位给悬浮关闭按钮，标题本身仍与下方区块左对齐到同一条竖线。
    .padding({ right: CLOSE_BUTTON_SIZE + 12 })
  }

  @Builder
  HeroSection() {
    Column({ space: 14 }) {
      Column({ space: 6 }) {
        Text(this.config.copy.offerTitle)
          .fontSize(24)
          .fontWeight(FontWeight.Bolder)
          .fontColor(this.theme.titleText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.config.copy.offerSubtitle)
          .fontSize(13)
          .lineHeight(20)
          .fontColor(this.theme.buttonText)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.config.metrics.length > 0) {
        Row({ space: 10 }) {
          ForEach(this.config.metrics, (metric: IapPaywallMetric) => {
            this.HeroMetric(metric)
          }, (metric: IapPaywallMetric, index: number) => `${index}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HeroMetric(metric: IapPaywallMetric) {
    Column({ space: 3 }) {
      Text(metric.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.accentColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(metric.label)
        .fontSize(11)
        .fontColor(this.theme.buttonText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(66)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.resolveCardSurfaceAlt('rgba(255,255,255,0.72)'))
    .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
    .borderRadius(14)
  }

  @Builder
  CloseButton() {
    // 悬浮层跟随内容列而不是屏幕右缘：宽屏下内容被 CONTENT_MAX_WIDTH 收窄居中，
    // 贴屏幕右缘的关闭按钮会离标题很远，显得与页面脱节。
    Row() {
      Row() {
        Row() {
          Text('✕')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleText)
        }
        .width(CLOSE_BUTTON_SIZE)
        .height(CLOSE_BUTTON_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('rgba(128,128,128,0.15)')
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(CLOSE_BUTTON_SIZE / 2)
        .onClick(() => {
          this.onClose()
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
      .justifyContent(FlexAlign.End)
      .padding({ right: CONTENT_GUTTER })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    // 与首行头像视觉居中对齐：内容顶距 + (头像高 - 按钮高) / 2
    .margin({ top: CLOSE_BUTTON_TOP })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  ProStatusView() {
    Column({ space: SECTION_SPACE }) {
      Row({ space: 14 }) {
        Row() {
          Text(this.config.proName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.buttonTextActive)
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.theme.accentColor)
        .borderRadius(18)

        Column({ space: 6 }) {
          Text(this.config.copy.proActivatedTitle)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 8 }) {
            Text(this.proStatusText || this.config.copy.memberExpiresHint)
              .fontSize(12)
              .fontColor(this.theme.buttonText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.proExpiresText)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.accentColor)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding(16)
      .backgroundColor(this.resolveHighlightSurface(HERO_WARM_BACKGROUND))
      .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
      .borderRadius(20)
      .shadow({ radius: 14, color: PAYWALL_CARD_SHADOW, offsetX: 0, offsetY: 6 })

      if (this.config.benefits.length > 0) {
        Column({ space: 10 }) {
          this.SectionTitle(this.config.copy.benefitsTitle || this.config.copy.offerTitle)

          Column({ space: 14 }) {
            ForEach(this.config.benefits, (benefit: IapPaywallBenefit) => {
              this.UnlockedFeatureItem(benefit)
            }, (benefit: IapPaywallBenefit, index: number) => `${index}-${benefit.icon}`)
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.theme.panelBackground)
          .border({ width: 1, color: this.theme.bodyBorder })
          .borderRadius(18)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Column({ space: 12 }) {
        Button(this.config.copy.startPlaying, { type: ButtonType.Normal })
          .width('100%')
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.buttonTextActive)
          .backgroundColor(this.theme.accentColor)
          .borderRadius(26)
          .onClick(() => {
            this.onClose()
          })

        if (this.canManageSubscription()) {
          Button(this.config.copy.manageSubscription, { type: ButtonType.Normal })
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.buttonText)
            .backgroundColor(this.theme.buttonNormal)
            .border({ width: 1, color: this.theme.bodyBorder })
            .borderRadius(24)
            .onClick(() => {
              this.handleManageSubscription()
            })
        }
      }
      .width('100%')

      this.FooterSection()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  UnlockedFeatureItem(benefit: IapPaywallBenefit) {
    Row({ space: 12 }) {
      Row() {
        Text(benefit.icon)
          .fontSize(18)
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveHighlightSurface(HERO_WARM_BACKGROUND))
      .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
      .borderRadius(13)

      Column({ space: 3 }) {
        Text(benefit.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
        if (benefit.description) {
          Text(benefit.description)
            .fontSize(12)
            .fontColor(this.theme.buttonText)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  SectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(19)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.theme.titleText)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  BenefitsSection() {
    if (this.config.benefits.length > 0) {
      Column({ space: 10 }) {
        this.SectionTitle(this.config.copy.benefitsTitle || this.config.copy.offerTitle)

        Column({ space: 8 }) {
          ForEach(this.config.benefits, (benefit: IapPaywallBenefit, index: number) => {
            this.BenefitItem(benefit, index)
          }, (benefit: IapPaywallBenefit, index: number) => `${index}-${benefit.icon}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ComparisonSection() {
    if (this.comparisonRowCount() > 0) {
      Column({ space: 10 }) {
        this.SectionTitle(this.config.copy.comparisonTitle || this.config.copy.offerTitle)

        Column() {
          Row() {
            Text(this.config.copy.comparisonBenefitHeader || this.config.copy.membershipLabel)
              .layoutWeight(5)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.titleText)
            Text(this.config.copy.comparisonVipHeader || this.config.proName)
              .layoutWeight(4)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.accentColor)
              .textAlign(TextAlign.Center)
            Text(this.config.copy.comparisonFreeHeader || this.config.copy.membershipLabel)
              .layoutWeight(4)
              .fontSize(13)
              .fontColor(this.theme.buttonText)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height(COMPARISON_ROW_HEIGHT)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.resolveCardSurfaceAlt(this.theme.buttonNormal))

          ForEach(this.comparisonRowList(), (row: IapPaywallComparisonRow, index: number) => {
            Row() {
              Text(row.label)
                .layoutWeight(5)
                .fontSize(14)
                .fontColor(this.theme.titleText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.vipValue)
                .layoutWeight(4)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.accentColor)
                .textAlign(TextAlign.Center)
                .maxLines(1)
              Text(row.freeValue)
                .layoutWeight(4)
                .fontSize(14)
                .fontColor(this.theme.buttonText)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            }
            .width('100%')
            .height(COMPARISON_ROW_HEIGHT)
            .padding({ left: 16, right: 16 })
            // 最后一行不画分隔线，避免与卡片圆角边框重叠成双线。
            .border({
              width: { bottom: index < this.comparisonRowCount() - 1 ? 1 : 0 },
              color: this.theme.bodyBorder
            })
          }, (row: IapPaywallComparisonRow, index: number) => `${index}`)
        }
        .width('100%')
        .backgroundColor(this.theme.panelBackground)
        .border({ width: 1, color: this.theme.bodyBorder })
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private comparisonRowList(): IapPaywallComparisonRow[] {
    return this.config.comparisonRows || []
  }

  private comparisonRowCount(): number {
    return this.comparisonRowList().length
  }

  /** 页脚合订：合规文案 + 协议/客服入口 + 恢复购买，内部用更紧的 10vp 节奏。 */
  @Builder
  FooterSection() {
    Column({ space: 10 }) {
      Divider()
        .strokeWidth(1)
        .color(this.theme.bodyBorder)
        .width('100%')
      this.FooterLegalText()
      this.SubscriptionInfoText()
      this.RestoreButton()
    }
    .width('100%')
    .padding({ top: 4 })
  }

  @Builder
  FooterLegalText() {
    Text(this.config.copy.legalFooter || this.config.copy.purchaseAgreePrefix)
      .fontSize(11)
      .lineHeight(16)
      .fontColor(this.theme.buttonText)
      .opacity(0.72)
      .textAlign(TextAlign.Center)
      .width('100%')
  }

  @Builder
  BenefitItem(benefit: IapPaywallBenefit, index: number) {
    Row({ space: 12 }) {
      Row() {
        Text(benefit.icon)
          .fontSize(19)
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveHighlightSurface(HERO_WARM_BACKGROUND))
      .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
      .borderRadius(13)

      Column({ space: 3 }) {
        Text(benefit.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (benefit.description) {
          Text(benefit.description)
            .fontSize(12)
            .lineHeight(17)
            .fontColor(this.theme.buttonText)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.resolveCardSurfaceAlt(BENEFIT_ROW_BACKGROUND))
    .border({ width: 1, color: this.theme.bodyBorder })
    .borderRadius(16)
  }

  @Builder
  PlanSelector() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.config.copy.planSectionTitle || this.config.copy.offerTitle)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.isLoadingProducts) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.theme.buttonText)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.isCompactLayout) {
        // 窄屏：整行卡片，价格右对齐成一条竖线，天然对齐。
        Column({ space: 10 }) {
          if (this.showTrialOption) {
            this.TrialPlanRow()
          }
          ForEach(this.products, (product: IapPaywallProduct) => {
            this.PlanRow(product)
          }, (product: IapPaywallProduct) => getPaywallItemKey(product, this.selectedPlan, this.isTrialSelected))
        }
        .width('100%')
      } else {
        // 宽屏：等宽分栏铺满内容宽度（不再是固定 154vp + 横向滚动导致的居中漂移）。
        Row({ space: 10 }) {
          if (this.showTrialOption) {
            this.TrialPlanColumn()
          }
          ForEach(this.products, (product: IapPaywallProduct) => {
            this.PlanColumn(product)
          }, (product: IapPaywallProduct) => getPaywallItemKey(product, this.selectedPlan, this.isTrialSelected))
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 宽屏分栏卡：四个槽位（标题/价格/说明/角标）恒定存在，跨卡基线严格对齐。 */
  @Builder
  PlanColumn(product: IapPaywallProduct) {
    Column({ space: 6 }) {
      Text(this.getPlanTitleText(product))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.titleText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(product.priceLabel)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.titleText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(product.dailyValueLabel || product.hintText || this.getPlanHintText(product))
        .fontSize(11)
        .fontColor(this.theme.buttonText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      // 角标槽位恒定占位：有无折扣角标都不改变上方三行的位置。
      Row() {
        if (product.discountLabel.length > 0) {
          this.PlanTag(product.discountLabel, this.theme.accentColor)
        }
      }
      .height(PLAN_TAG_SLOT_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .height(PLAN_CARD_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.isPurchasePlanSelected(product)
      ? this.resolveHighlightSurface(SELECTED_PLAN_BACKGROUND) : this.resolveCardSurface(PLAN_CARD_BACKGROUND))
    .borderRadius(16)
    // 边框宽度恒定，选中只换颜色，避免选中时内容整体位移 1vp。
    .border({
      width: PLAN_CARD_BORDER,
      color: this.isPurchasePlanSelected(product) ? this.theme.accentColor : this.theme.bodyBorder
    })
    .shadow(this.isPurchasePlanSelected(product)
      ? { radius: 18, color: PAYWALL_CARD_SHADOW, offsetX: 0, offsetY: 8 } : undefined)
    .onClick(() => {
      this.selectPlan(product)
    })
  }

  @Builder
  TrialPlanColumn() {
    Column({ space: 6 }) {
      Text(this.trialCtaLabel)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.titleText)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(this.config.copy.trialFreeLabel || this.trialCtaLabel)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.accentColor)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(this.config.copy.trialPeriodLabel || this.config.copy.trialFreeHint || '')
        .fontSize(11)
        .fontColor(this.theme.buttonText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      Row()
        .height(PLAN_TAG_SLOT_HEIGHT)
    }
    .layoutWeight(1)
    .height(PLAN_CARD_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.isTrialSelected
      ? this.resolveHighlightSurface(SELECTED_PLAN_BACKGROUND) : this.resolveCardSurface(PLAN_CARD_BACKGROUND))
    .borderRadius(16)
    .border({
      width: PLAN_CARD_BORDER,
      color: this.isTrialSelected ? this.theme.accentColor : this.theme.bodyBorder
    })
    .shadow(this.isTrialSelected
      ? { radius: 18, color: PAYWALL_CARD_SHADOW, offsetX: 0, offsetY: 8 } : undefined)
    .onClick(() => {
      this.selectTrial()
    })
  }

  /** 窄屏整行卡：左侧单选点 + 名称，右侧价格与角标右对齐。 */
  @Builder
  PlanRow(product: IapPaywallProduct) {
    Row({ space: 12 }) {
      this.SelectionDot(this.isPurchasePlanSelected(product))

      Column({ space: 4 }) {
        Text(this.getPlanTitleText(product))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(product.dailyValueLabel || product.hintText || this.getPlanHintText(product))
          .fontSize(12)
          .fontColor(this.theme.buttonText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text(product.priceLabel)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .maxLines(1)
        if (product.discountLabel.length > 0) {
          this.PlanTag(product.discountLabel, this.theme.accentColor)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(PLAN_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.isPurchasePlanSelected(product)
      ? this.resolveHighlightSurface(SELECTED_PLAN_BACKGROUND) : this.resolveCardSurface(PLAN_CARD_BACKGROUND))
    .borderRadius(16)
    .border({
      width: PLAN_CARD_BORDER,
      color: this.isPurchasePlanSelected(product) ? this.theme.accentColor : this.theme.bodyBorder
    })
    .onClick(() => {
      this.selectPlan(product)
    })
  }

  @Builder
  TrialPlanRow() {
    Row({ space: 12 }) {
      this.SelectionDot(this.isTrialSelected)

      Column({ space: 4 }) {
        Text(this.trialCtaLabel)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.config.copy.trialFreeHint || this.trialSubLabel)
          .fontSize(12)
          .fontColor(this.theme.buttonText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text(this.config.copy.trialFreeLabel || this.trialCtaLabel)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.accentColor)
          .maxLines(1)
        Text(this.config.copy.trialPeriodLabel || '')
          .fontSize(11)
          .fontColor(this.theme.buttonText)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(PLAN_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.isTrialSelected
      ? this.resolveHighlightSurface(SELECTED_PLAN_BACKGROUND) : this.resolveCardSurface(PLAN_CARD_BACKGROUND))
    .borderRadius(16)
    .border({
      width: PLAN_CARD_BORDER,
      color: this.isTrialSelected ? this.theme.accentColor : this.theme.bodyBorder
    })
    .onClick(() => {
      this.selectTrial()
    })
  }

  @Builder
  SelectionDot(selected: boolean) {
    Row() {
      if (selected) {
        Text('✓')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.buttonTextActive)
      }
    }
    .width(22)
    .height(22)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(selected ? this.theme.accentColor : Color.Transparent)
    .border({ width: 1.5, color: selected ? this.theme.accentColor : this.theme.bodyBorder })
    .borderRadius(11)
  }

  @Builder
  PlanTag(label: ResourceStr, color: ResourceColor) {
    Text(label)
      .fontSize(10)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor(color)
      .borderRadius(7)
  }

  private selectPlan(product: IapPaywallProduct): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      const wasTrial = this.isTrialSelected
      this.isTrialSelected = false
      if (wasTrial || this.selectedPlan !== product.plan) {
        this.selectedPlan = product.plan
        this.agreedPurchaseTerms = false
      }
    })
  }

  private selectTrial(): void {
    if (this.isTrialSelected) {
      return
    }
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.isTrialSelected = true
      this.agreedPurchaseTerms = false
    })
  }

  private isPurchasePlanSelected(product: IapPaywallProduct): boolean {
    return this.isPlanSelected(product) && !this.isTrialSelected
  }

  private isPlanSelected(product: IapPaywallProduct): boolean {
    return this.selectedPlan === product.plan
  }

  private getPlanTitleText(product: IapPaywallProduct): ResourceStr {
    if (product.title) {
      return product.title
    }
    if (product.plan === IapPaywallPlan.MONTHLY) {
      return this.config.copy.monthlyPlanTitle
    }
    if (product.plan === IapPaywallPlan.YEARLY) {
      return this.config.copy.yearlyPlanTitle
    }
    return this.config.copy.lifetimePlanTitle
  }

  private getPlanHintText(product: IapPaywallProduct): ResourceStr {
    if (product.hintText) {
      return product.hintText
    }
    if (product.plan === IapPaywallPlan.YEARLY) {
      return this.config.copy.yearlyHint
    }
    if (product.plan === IapPaywallPlan.LIFETIME) {
      return this.config.copy.lifetimeHint
    }
    return this.config.copy.monthlyHint
  }

  private requiresAutoRenewConsent(): boolean {
    return !this.isTrialSelected && this.selectedPlan !== IapPaywallPlan.LIFETIME
  }

  private canManageSubscription(): boolean {
    const status = this.proStatusText.toString().toLowerCase()
    return !status.includes('lifetime') && !status.includes('trial')
  }

  private canPurchaseSelectedPlan(): boolean {
    const isWorking = this.isPurchasing || this.isStartingTrial
    const selectedProduct = this.products.find((product: IapPaywallProduct) => product.plan === this.selectedPlan)
    const hasRequiredDisclosure = this.isTrialSelected || this.agreedPurchaseTerms
    const available = this.isTrialSelected || (this.isEnvironmentReady && !this.isPurchaseCoolingDown())
    return hasRequiredDisclosure && !isWorking && available &&
      (this.isTrialSelected || (this.productSource === IapPaywallProductSource.LIVE_STORE &&
      selectedProduct !== undefined && isPurchasablePaywallProduct(selectedProduct)))
  }

  @Builder
  SelectedPlanNotice() {
    Row({ space: 8 }) {
      Text('i')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.accentColor)
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.resolveHighlightSurface(HERO_WARM_BACKGROUND))
        .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
        .borderRadius(10)
      Text(this.getSelectedPlanNoticeText())
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.theme.buttonText)
        .layoutWeight(1)
    }
    .width('100%')
    // 说明文案可能折行，图标与首行顶部对齐而不是整体居中。
    .alignItems(VerticalAlign.Top)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.resolveHighlightSurface('#FFFBF5'))
    .border({ width: 1, color: this.resolveHighlightBorder(HERO_WARM_ACCENT) })
    .borderRadius(14)
  }

  private getSelectedPlanNoticeText(): ResourceStr {
    if (this.isTrialSelected) {
      return this.trialSubLabel
    }
    return this.requiresAutoRenewConsent() ? this.config.copy.selectedSubscriptionNotice :
      this.config.copy.selectedLifetimeNotice
  }

  @Builder
  PurchaseTermsConsent() {
    Row({ space: 10 }) {
      Row() {
        if (this.agreedPurchaseTerms) {
          Text('✓')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.buttonTextActive)
        }
      }
      .width(22)
      .height(22)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.agreedPurchaseTerms ? this.theme.accentColor : Color.Transparent)
      .border({
        width: 1.5,
        color: this.agreedPurchaseTerms ? this.theme.accentColor : this.theme.bodyBorder
      })
      .borderRadius(11)
      .onClick(() => {
        animateTo({ duration: 150 }, () => {
          this.agreedPurchaseTerms = !this.agreedPurchaseTerms
        })
      })

      Text() {
        Span(this.requiresAutoRenewConsent() ? this.config.copy.autoRenewAgreePrefix :
          this.config.copy.purchaseTermsAgreePrefix)
          .fontSize(12)
          .fontColor(this.theme.buttonText)
        Span(this.requiresAutoRenewConsent() ? this.config.copy.autoRenewAgreementLink :
          this.config.copy.userAgreement)
          .fontSize(12)
          .fontColor(this.theme.accentColor)
          .decoration({ type: TextDecorationType.Underline, color: this.theme.accentColor })
          .onClick(() => {
            this.openUrl(this.config.termsUrl)
          })
        Span(this.requiresAutoRenewConsent() ? this.config.copy.autoRenewAgreeSuffix :
          this.config.copy.purchaseTermsAgreeSuffix)
          .fontSize(12)
          .fontColor(this.theme.buttonText)
      }
      .lineHeight(18)
      .layoutWeight(1)
      .onClick(() => {
        animateTo({ duration: 150 }, () => {
          this.agreedPurchaseTerms = !this.agreedPurchaseTerms
        })
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.resolveCardSurface(PLAN_CARD_BACKGROUND))
    .border({ width: 1, color: this.theme.bodyBorder })
    .borderRadius(14)
  }

  @Builder
  SubscriptionInfoText() {
    Column({ space: 6 }) {
      if (this.requiresAutoRenewConsent()) {
        Text(this.config.copy.subscriptionAutoRenewHint)
          .fontSize(11)
          .lineHeight(16)
          .fontColor(this.theme.buttonText)
          .opacity(0.85)
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      Text() {
        Span(this.config.copy.purchaseAgreePrefix)
          .fontSize(11)
          .fontColor(this.theme.buttonText)
        Span(this.config.copy.privacyPolicy)
          .fontSize(11)
          .fontColor(this.theme.accentColor)
          .decoration({ type: TextDecorationType.Underline, color: this.theme.accentColor })
          .onClick(() => {
            this.openUrl(this.config.privacyUrl)
          })
        Span(this.config.copy.purchaseAgreeAnd)
          .fontSize(11)
          .fontColor(this.theme.buttonText)
        Span(this.config.copy.userAgreement)
          .fontSize(11)
          .fontColor(this.theme.accentColor)
          .decoration({ type: TextDecorationType.Underline, color: this.theme.accentColor })
          .onClick(() => {
            this.openUrl(this.config.termsUrl)
          })
      }
      .lineHeight(16)
      .textAlign(TextAlign.Center)
      .width('100%')
      .opacity(0.85)

      Text() {
        Span(this.config.copy.supportEmailLabel)
          .fontSize(11)
          .fontColor(this.theme.buttonText)
        Span(this.config.supportEmail)
          .fontSize(11)
          .fontColor(this.theme.accentColor)
      }
      .lineHeight(16)
      .textAlign(TextAlign.Center)
      .width('100%')
      .opacity(0.85)
    }
    .width('100%')
  }

  @Builder
  PurchaseButton() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        if (this.isPurchasing || this.isStartingTrial) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.canPurchaseSelectedPlan() ? this.theme.buttonTextActive : this.theme.buttonText)
        }
        Text((this.isPurchasing || this.isStartingTrial) ? this.config.copy.purchasing : this.getPurchaseButtonLabel())
          .fontSize(18)
          .fontWeight(FontWeight.Bolder)
          .fontColor(this.canPurchaseSelectedPlan() ? this.theme.buttonTextActive : this.theme.buttonText)
      }
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.canPurchaseSelectedPlan() ? this.theme.accentColor : this.resolveCardSurfaceAlt(BENEFIT_ROW_BACKGROUND))
    .border({
      width: this.canPurchaseSelectedPlan() ? 0 : 1,
      color: this.canPurchaseSelectedPlan() ? Color.Transparent : this.theme.bodyBorder
    })
    .borderRadius(28)
    .shadow(this.canPurchaseSelectedPlan() ?
      { radius: 20, color: PAYWALL_CARD_SHADOW, offsetX: 0, offsetY: 8 } : undefined)
    .scale({ x: (this.isPurchasing || this.isStartingTrial) ? 0.98 : 1, y: (this.isPurchasing || this.isStartingTrial) ? 0.98 : 1 })
    .animation({ duration: 150 })
    .enabled(this.canPurchaseSelectedPlan())
    .onClick(() => {
      if (this.isTrialSelected) {
        this.handleStartTrial()
      } else {
        this.handlePurchase()
      }
    })
  }

  @Builder
  EnvironmentWarningBanner() {
    Row({ space: 8 }) {
      Text('⚠')
        .fontSize(16)
        .fontColor('#FF8C00')
      Text(this.config.copy.iapEnvWarning)
        .fontSize(12)
        .fontColor(this.theme.buttonText)
        .layoutWeight(1)
      Text(this.config.copy.iapRetry)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.accentColor)
        .onClick(() => {
          this.retryEnvironmentCheck()
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.theme.panelBackground)
    .border({ width: 1, color: '#FF8C00' })
    .borderRadius(12)
  }

  @Builder
  RestoreButton() {
    Text(this.config.copy.restorePurchase)
      .fontSize(13)
      .fontColor(this.theme.buttonText)
      .decoration({ type: TextDecorationType.Underline, color: this.theme.buttonText })
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.handleRestore()
      })
  }

  private async handleStartTrial(): Promise<void> {
    if (this.isStartingTrial) {
      return
    }
    this.isStartingTrial = true
    try {
      const started = await this.onStartTrial()
      if (started) {
        this.entitlementRestored = true
        this.showToast(this.trialSuccessToast, 3000)
        this.onPurchaseSucceeded()
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Start trial error: ' + String(err))
    } finally {
      this.isStartingTrial = false
    }
  }

  private async handlePurchase(): Promise<void> {
    if (this.isPurchaseCoolingDown()) {
      this.showToast(this.config.copy.purchaseCoolingDown, 1500)
      return
    }

    if (!this.agreedPurchaseTerms) {
      this.showToast(this.config.copy.purchaseTermsRequired, 2000)
      return
    }

    if (this.isPurchasing) {
      return
    }
    this.isPurchasing = true
    const context = getContext(this) as common.UIAbilityContext

    try {
      const selectedProduct = this.products.find((product: IapPaywallProduct) => product.plan === this.selectedPlan)
      if (!selectedProduct || this.productSource !== IapPaywallProductSource.LIVE_STORE ||
        !isPurchasablePaywallProduct(selectedProduct)) {
        hilog.error(0x0000, TAG, 'Selected paywall product is unavailable')
        return
      }
      const success = await this.adapter.purchase(context, selectedProduct)
      if (!this.isPaywallVisible) {
        return
      }
      if (success) {
        this.entitlementRestored = true
        this.showToast(this.config.copy.purchaseSuccessToast, 3000)
        this.onPurchaseSucceeded()
      } else {
        this.startPurchaseCooldown(PURCHASE_COOLDOWN_SECONDS)
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Purchase error: ' + String(err))
      const errMsg = err instanceof Error ? err.message : String(err)
      if (!this.isPaywallVisible) {
        return
      }
      if (errMsg === 'IAP_ENV_NOT_READY') {
        this.isEnvironmentReady = false
        this.showToast(this.config.copy.iapEnvErrorToast, 3000)
      } else if (errMsg === (this.config.subscriptionManageErrorCode || IAP_PAYWALL_TOO_FREQUENT_ERROR)) {
        this.startPurchaseCooldown(PURCHASE_THROTTLE_COOLDOWN_SECONDS)
        this.showToast(this.config.copy.purchaseTooFrequent, 2500)
      } else if (errMsg === IAP_PAYWALL_PAYMENT_PENDING_ERROR) {
        this.showToast(this.config.copy.purchasePendingToast || '支付已完成，权益同步中，请稍后查看', 3500)
        this.entitlementRestored = false
        const recovery = await this.pendingRecovery.run(
          () => this.adapter.restorePurchases(context),
          () => hilog.warn(0x0000, TAG, 'Pending purchase recovery will retry'))
        if (recovery === PurchaseRecoveryResult.RECOVERED) {
          this.entitlementRestored = true
          this.showToast(this.config.copy.purchaseSuccessToast, 3000)
          this.onPurchaseSucceeded()
        } else if (recovery === PurchaseRecoveryResult.EXHAUSTED) {
          this.showToast(this.config.copy.purchasePendingToast || DEFAULT_CONFIG.copy.purchasePendingToast!, 3500)
        }
      } else {
        this.showToast(this.config.copy.purchaseLaunchFailedPrefix, 3000)
      }
    } finally {
      this.isPurchasing = false
    }
  }

  private isPurchaseCoolingDown(): boolean {
    return this.purchaseCooldownRemainingSec > 0
  }

  private startPurchaseCooldown(seconds: number): void {
    this.clearPurchaseCooldownTimer()
    this.purchaseCooldownRemainingSec = seconds
    this.purchaseCooldownTimer = setInterval(() => {
      if (this.purchaseCooldownRemainingSec <= 1) {
        this.purchaseCooldownRemainingSec = 0
        this.clearPurchaseCooldownTimer()
        return
      }
      this.purchaseCooldownRemainingSec -= 1
    }, 1000) as number
  }

  private clearPurchaseCooldownTimer(): void {
    if (this.purchaseCooldownTimer >= 0) {
      clearInterval(this.purchaseCooldownTimer)
      this.purchaseCooldownTimer = -1
    }
  }

  private onIsProChanged(): void {
    this.entitlementRestored = this.isPro
  }

  private shouldShowProStatus(): boolean {
    return this.isPro || this.entitlementRestored
  }

  private showToast(message: ResourceStr, duration: number): void {
    try {
      promptAction.showToast({ message, duration })
    } catch (err) {
      hilog.error(0x0000, TAG, 'Show toast error: ' + String(err))
    }
  }

  private async handleRestore(): Promise<void> {
    if (this.isPurchasing) {
      return
    }
    this.isPurchasing = true
    try {
      const context = getContext(this) as common.UIAbilityContext
      const restored = await this.adapter.restorePurchases(context)
      if (!this.isPaywallVisible) {
        return
      }
      if (restored) {
        this.entitlementRestored = true
        this.showToast(this.config.copy.restoreSuccessToast, 2000)
        this.onRestoreSucceeded()
      } else {
        this.showToast(this.config.copy.restoreEmptyToast, 2000)
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Restore error: ' + String(err))
      this.showToast(this.config.copy.iapEnvErrorToast, 3000)
    } finally {
      this.isPurchasing = false
    }
  }

  private async retryEnvironmentCheck(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const envOk = await this.adapter.checkEnvironment(context)
      this.isEnvironmentReady = envOk
      if (envOk) {
        this.showToast(this.config.copy.iapEnvReady, 2000)
        await this.loadProducts()
      } else {
        this.showToast(this.config.copy.iapEnvRetryFailed, 2000)
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Retry env check error: ' + String(err))
    }
  }

  private async handleManageSubscription(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      await this.adapter.manageSubscriptions(context)
    } catch (err) {
      hilog.error(0x0000, TAG, 'Manage subscription error: ' + String(err))
    }
  }

  private openUrl(url: string): void {
    if (url.length === 0) {
      return
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      const options: OpenLinkOptions = { appLinkingOnly: false }
      context.openLink(url, options)
        .catch((err: Error) => {
          hilog.error(0x0000, TAG, `openLink failed: ${err.message}`)
        })
    } catch (err) {
      hilog.error(0x0000, TAG, 'Open URL error: ' + String(err))
    }
  }

  private getPurchaseButtonLabel(): ResourceStr {
    if (this.isPurchaseCoolingDown()) {
      return this.config.copy.purchaseRetryLater
    }
    if (this.isTrialSelected) {
      return this.trialCtaLabel
    }
    const selectedProduct = this.products.find((product: IapPaywallProduct) => product.plan === this.selectedPlan)
    if (selectedProduct && this.hasValidCtaFormat(selectedProduct)) {
      return selectedProduct.ctaFormat!.replace('%s', selectedProduct.priceLabel)
    }
    if (this.selectedPlan === IapPaywallPlan.LIFETIME) {
      return this.config.copy.purchaseNow
    }
    return this.config.copy.subscribeNow
  }

  private hasValidCtaFormat(product: IapPaywallProduct): boolean {
    const format = product.ctaFormat || ''
    return format.indexOf('%s') >= 0 && format.indexOf('%s') === format.lastIndexOf('%s')
  }
}
