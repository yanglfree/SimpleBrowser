import {
  IapPaywallConfig,
  IapPaywallComparisonRow,
  IapPaywallPlan,
  IapPaywallTheme,
  StandardIapPaywallPage
} from 'iap_paywall_kit';

import { ProBillingAdapter } from '../services/ProBillingAdapter';

const SUPPORT_EMAIL: string = 'youdroid2048@gmail.com';
const TERMS_URL: string = 'https://browser.youdroid.top/terms.html';
const PRIVACY_URL: string = 'https://browser.youdroid.top/privacy.html';

@Component
export struct ZhuoProPaywall {
  @Prop isPro: boolean = false;
  @Prop proExpiresText: ResourceStr = '';
  onClose: () => void = (): void => {};
  onEntitlementChanged: () => void = (): void => {};
  private adapter: ProBillingAdapter = new ProBillingAdapter();

  build() {
    StandardIapPaywallPage({
      theme: this.theme(),
      config: this.config(),
      adapter: this.adapter,
      isPro: this.isPro,
      proStatusText: $r('app.string.pro_settings_active'),
      proExpiresText: this.proExpiresText,
      onClose: (): void => this.onClose(),
      onPurchaseSucceeded: (): void => this.onEntitlementChanged(),
      onRestoreSucceeded: (): void => this.onEntitlementChanged()
    });
  }

  private theme(): IapPaywallTheme {
    return {
      bodyBackground: $r('app.color.page_background'),
      bodyBorder: $r('app.color.border'),
      panelBackground: $r('app.color.surface_panel'),
      buttonNormal: $r('app.color.surface_subtle'),
      buttonText: $r('app.color.text_secondary'),
      buttonTextActive: $r('app.color.accent_foreground'),
      accentColor: $r('app.color.accent'),
      titleText: $r('app.color.text_primary'),
      cardBackground: $r('app.color.surface_panel'),
      cardBackgroundAlt: $r('app.color.surface_subtle'),
      highlightSurface: $r('app.color.surface_subtle'),
      highlightBorder: $r('app.color.accent')
    };
  }

  private config(): IapPaywallConfig {
    return {
      appName: $r('app.string.app_name'),
      proName: $r('app.string.pro_comparison_pro'),
      supportEmail: SUPPORT_EMAIL,
      termsUrl: TERMS_URL,
      privacyUrl: PRIVACY_URL,
      defaultSelectedPlan: IapPaywallPlan.YEARLY,
      defaultProducts: [],
      metrics: [],
      benefits: [
        {
          icon: '📚',
          title: $r('app.string.pro_benefit_offline'),
          description: $r('app.string.pro_benefit_offline_desc')
        },
        {
          icon: '✍️',
          title: $r('app.string.pro_benefit_organize'),
          description: $r('app.string.pro_benefit_organize_desc')
        },
        {
          icon: '↗',
          title: $r('app.string.pro_benefit_export'),
          description: $r('app.string.pro_benefit_export_desc')
        }
      ],
      comparisonRows: [
        this.comparisonRow($r('app.string.pro_compare_clean'), true),
        this.comparisonRow($r('app.string.pro_compare_reader'), true),
        this.comparisonRow($r('app.string.pro_compare_library'), false),
        this.comparisonRow($r('app.string.pro_compare_annotations'), false)
      ],
      copy: {
        planSectionTitle: $r('app.string.pro_plan_section'),
        benefitsTitle: $r('app.string.pro_benefits_title'),
        comparisonTitle: $r('app.string.pro_comparison_title'),
        comparisonBenefitHeader: $r('app.string.pro_comparison_feature'),
        comparisonVipHeader: $r('app.string.pro_comparison_pro'),
        comparisonFreeHeader: $r('app.string.pro_comparison_free'),
        legalFooter: $r('app.string.pro_legal_footer'),
        membershipLabel: $r('app.string.pro_membership_label'),
        heroTitleSuffix: $r('app.string.pro_hero_suffix'),
        heroSubtitle: $r('app.string.pro_hero_subtitle'),
        offerTitle: $r('app.string.pro_offer_title'),
        offerSubtitle: $r('app.string.pro_offer_subtitle'),
        monthlyPlanTitle: $r('app.string.pro_monthly_title'),
        yearlyPlanTitle: $r('app.string.pro_yearly_title'),
        lifetimePlanTitle: $r('app.string.pro_lifetime_title'),
        monthlyHint: $r('app.string.pro_monthly_hint'),
        yearlyHint: $r('app.string.pro_yearly_hint'),
        lifetimeHint: $r('app.string.pro_lifetime_hint'),
        selectedSubscriptionNotice: $r('app.string.pro_subscription_notice'),
        selectedLifetimeNotice: $r('app.string.pro_lifetime_notice'),
        autoRenewAgreePrefix: $r('app.string.pro_consent_prefix'),
        autoRenewAgreementLink: $r('app.string.pro_auto_renew_link'),
        autoRenewAgreeSuffix: $r('app.string.pro_auto_renew_suffix'),
        purchaseTermsAgreePrefix: $r('app.string.pro_consent_prefix'),
        purchaseTermsAgreeSuffix: $r('app.string.pro_purchase_terms_suffix'),
        subscriptionAutoRenewHint: $r('app.string.pro_subscription_hint'),
        purchaseAgreePrefix: $r('app.string.pro_purchase_agree_prefix'),
        purchaseAgreeAnd: $r('app.string.pro_purchase_agree_and'),
        privacyPolicy: $r('app.string.pro_privacy_policy'),
        userAgreement: $r('app.string.pro_user_agreement'),
        supportEmailLabel: $r('app.string.pro_support_email_label'),
        agreeTermsToContinue: $r('app.string.pro_agree_to_continue'),
        subscribeNow: $r('app.string.pro_subscribe_now'),
        purchaseNow: $r('app.string.pro_purchase_now'),
        purchasing: $r('app.string.pro_purchasing'),
        restorePurchase: $r('app.string.pro_restore_purchase'),
        manageSubscription: $r('app.string.pro_manage_subscription'),
        startPlaying: $r('app.string.pro_start_using'),
        proActivatedTitle: $r('app.string.pro_activated_title'),
        memberExpiresHint: $r('app.string.pro_expires_hint'),
        purchaseTermsRequired: $r('app.string.pro_terms_required'),
        purchaseCoolingDown: $r('app.string.pro_purchase_cooling'),
        purchaseTooFrequent: $r('app.string.pro_purchase_frequent'),
        purchaseRetryLater: $r('app.string.pro_retry_later'),
        iapEnvWarning: $r('app.string.pro_iap_warning'),
        iapRetry: $r('app.string.pro_iap_retry'),
        iapEnvErrorToast: $r('app.string.pro_iap_error'),
        iapEnvRetryFailed: $r('app.string.pro_iap_retry_failed'),
        iapEnvReady: $r('app.string.pro_iap_ready'),
        purchaseSuccessToast: $r('app.string.pro_purchase_success'),
        restoreSuccessToast: $r('app.string.pro_restore_success'),
        restoreEmptyToast: $r('app.string.pro_restore_empty'),
        purchasePendingToast: $r('app.string.pro_purchase_pending'),
        purchaseLaunchFailedPrefix: $r('app.string.pro_purchase_failed_prefix')
      }
    };
  }

  private comparisonRow(label: ResourceStr, isFree: boolean): IapPaywallComparisonRow {
    return {
      label: label,
      vipValue: $r('app.string.pro_compare_yes'),
      freeValue: isFree ? $r('app.string.pro_compare_yes') : $r('app.string.pro_compare_no')
    };
  }
}
