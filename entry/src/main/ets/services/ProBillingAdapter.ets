import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import {
  IAP_PAYWALL_PAYMENT_PENDING_ERROR,
  IAP_PAYWALL_TOO_FREQUENT_ERROR,
  IapPaywallPlan,
  IapPaywallProduct,
  IapPaywallProductLoadResult,
  IapPaywallProductSource,
  IapPaywallPurchaseAdapter
} from 'iap_paywall_kit';

import {
  LIFETIME_PRODUCT_IDS,
  NON_CONSUMABLE_PRODUCT_TYPE,
  PRO_LIFETIME_PRODUCT_ID,
  PRO_MONTHLY_PRODUCT_ID,
  PRO_YEARLY_PRODUCT_ID,
  ProPurchaseEvidence,
  SUBSCRIPTION_PRODUCT_IDS,
  SUBSCRIPTION_PRODUCT_TYPE,
  isActiveProEntitlement,
  isKnownProProduct,
  productTypeForId
} from '../models/ProModels';
import { Logger } from '../utils/Logger';
import { ProEntitlementApiService } from './ProEntitlementApiService';
import { ProEntitlementService } from './ProEntitlementService';

const TAG: string = 'ProBilling';
const USER_CANCELED_CODE: number = 1001860006;
const ALREADY_OWNED_CODE: number = 1001860051;
const TOO_FREQUENT_CODE: number = 1001860004;

interface ProductCompat {
  id?: string;
  productId?: string;
  localPrice?: string;
  price?: string;
}

interface PurchasePayload {
  productId: string;
  purchaseToken: string;
  purchaseOrderId: string;
}

interface PendingPurchase {
  evidence: ProPurchaseEvidence;
  shouldFinish: boolean;
}

export class ProBillingAdapter implements IapPaywallPurchaseAdapter {
  private isEnvironmentReady: boolean = false;

  async checkEnvironment(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await iap.queryEnvironmentStatus(context);
      this.isEnvironmentReady = true;
    } catch (error) {
      Logger.warn(TAG, `IAP environment unavailable: ${this.formatError(error as Object)}`);
      this.isEnvironmentReady = false;
    }
    return this.isEnvironmentReady;
  }

  async queryProducts(context: common.UIAbilityContext): Promise<IapPaywallProductLoadResult> {
    if (!this.isEnvironmentReady && !await this.checkEnvironment(context)) {
      return { products: [], source: IapPaywallProductSource.FALLBACK };
    }
    try {
      const subscriptions = await iap.queryProducts(context, {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: SUBSCRIPTION_PRODUCT_IDS
      });
      const lifetime = await iap.queryProducts(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: LIFETIME_PRODUCT_IDS
      });
      const products: IapPaywallProduct[] = [];
      for (const product of [...subscriptions, ...lifetime]) {
        const mapped = this.mapProduct(product);
        if (mapped !== null) {
          products.push(mapped);
        }
      }
      return { products: products, source: IapPaywallProductSource.LIVE_STORE };
    } catch (error) {
      Logger.error(TAG, `Product query failed: ${this.formatError(error as Object)}`);
      return { products: [], source: IapPaywallProductSource.FALLBACK };
    }
  }

  async purchase(context: common.UIAbilityContext, product: IapPaywallProduct): Promise<boolean> {
    if (product.source !== IapPaywallProductSource.LIVE_STORE || !isKnownProProduct(product.productId)) {
      return false;
    }
    let storePurchaseCompleted: boolean = false;
    try {
      const result = await iap.createPurchase(context, {
        productType: productTypeForId(product.productId) as iap.ProductType,
        productId: product.productId
      });
      storePurchaseCompleted = true;
      const evidence = this.evidenceFromRaw(result.purchaseData);
      if (evidence === null) {
        throw new Error(IAP_PAYWALL_PAYMENT_PENDING_ERROR);
      }
      const verified = await ProEntitlementApiService.getInstance().verifyHarmonyPurchase(
        context,
        evidence,
        'purchase'
      );
      if (!verified.verified || !isActiveProEntitlement(verified.entitlement)) {
        throw new Error(IAP_PAYWALL_PAYMENT_PENDING_ERROR);
      }
      await ProEntitlementService.getInstance().applyServerEntitlement(context, verified.entitlement);
      if (verified.needsFinishTransaction) {
        await this.finishPurchase(context, evidence);
      }
      return true;
    } catch (error) {
      const code = this.errorCode(error as Object);
      if (code === USER_CANCELED_CODE) {
        return false;
      }
      if (!storePurchaseCompleted && code === ALREADY_OWNED_CODE) {
        return this.restorePurchases(context);
      }
      if (!storePurchaseCompleted && code === TOO_FREQUENT_CODE) {
        throw new Error(IAP_PAYWALL_TOO_FREQUENT_ERROR);
      }
      if (storePurchaseCompleted) {
        throw new Error(IAP_PAYWALL_PAYMENT_PENDING_ERROR);
      }
      throw new Error(this.formatError(error as Object));
    }
  }

  async restorePurchases(context: common.UIAbilityContext): Promise<boolean> {
    if (!this.isEnvironmentReady && !await this.checkEnvironment(context)) {
      return false;
    }
    const unfinished = await this.queryPurchases(context, iap.PurchaseQueryType.UNFINISHED, true);
    const current = await this.queryPurchases(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT, false);
    const purchases = this.deduplicate([...unfinished, ...current]);
    try {
      const api = ProEntitlementApiService.getInstance();
      let verificationFailed = false;
      for (const pending of purchases) {
        try {
          const result = await api.verifyHarmonyPurchase(context, pending.evidence, 'restore');
          if (result.verified && isActiveProEntitlement(result.entitlement)) {
            await ProEntitlementService.getInstance().applyServerEntitlement(context, result.entitlement);
            if (pending.shouldFinish && result.needsFinishTransaction) {
              await this.finishPurchase(context, pending.evidence);
            }
          }
        } catch (error) {
          verificationFailed = true;
          Logger.warn(TAG, 'Purchase verification deferred during restore');
        }
      }
      const entitlement = await api.fetchEntitlements(context);
      if (!isActiveProEntitlement(entitlement)) {
        if (verificationFailed) {
          throw new Error(IAP_PAYWALL_PAYMENT_PENDING_ERROR);
        }
        await ProEntitlementService.getInstance().applyServerEntitlement(context, null);
        return false;
      }
      await ProEntitlementService.getInstance().applyServerEntitlement(context, entitlement);
      Logger.info(TAG, 'Restore completed with a server-verified active entitlement');
      return true;
    } catch (error) {
      Logger.error(TAG, `Restore failed: ${this.formatError(error as Object)}`);
      throw new Error(IAP_PAYWALL_PAYMENT_PENDING_ERROR);
    }
  }

  async manageSubscriptions(context: common.UIAbilityContext): Promise<void> {
    await iap.showManagedSubscriptions(context, {
      windowScreenMode: iap.WindowScreenMode.FULLSCREEN
    });
  }

  async syncEntitlements(context: common.UIAbilityContext, reason: string): Promise<boolean> {
    if (!this.isEnvironmentReady && !await this.checkEnvironment(context)) {
      return ProEntitlementService.getInstance().refresh(context, reason);
    }
    const unfinished = await this.queryPurchases(context, iap.PurchaseQueryType.UNFINISHED, true);
    if (unfinished.length === 0) {
      return ProEntitlementService.getInstance().refresh(context, reason);
    }
    return this.restorePurchases(context);
  }

  private mapProduct(product: iap.Product): IapPaywallProduct | null {
    const compat = product as ProductCompat;
    const productId = compat.productId ?? compat.id ?? '';
    const price = compat.localPrice ?? compat.price ?? '';
    if (!isKnownProProduct(productId) || price.length === 0) {
      return null;
    }
    const plan = productId === PRO_MONTHLY_PRODUCT_ID ? IapPaywallPlan.MONTHLY :
      productId === PRO_YEARLY_PRODUCT_ID ? IapPaywallPlan.YEARLY : IapPaywallPlan.LIFETIME;
    return {
      productId: productId,
      plan: plan,
      priceLabel: price,
      originalPriceLabel: '',
      periodLabel: '',
      discountLabel: '',
      promoLabel: '',
      source: IapPaywallProductSource.LIVE_STORE,
      storePrice: price
    };
  }

  private async queryPurchases(
    context: common.UIAbilityContext,
    queryType: iap.PurchaseQueryType,
    shouldFinish: boolean
  ): Promise<PendingPurchase[]> {
    const pending: PendingPurchase[] = [];
    for (const productType of [NON_CONSUMABLE_PRODUCT_TYPE, SUBSCRIPTION_PRODUCT_TYPE]) {
      try {
        const result = await iap.queryPurchases(context, {
          productType: productType as iap.ProductType,
          queryType: queryType
        });
        for (const raw of result.purchaseDataList ?? []) {
          const evidence = this.evidenceFromRaw(raw);
          if (evidence !== null) {
            pending.push({ evidence: evidence, shouldFinish: shouldFinish });
          }
        }
      } catch (error) {
        Logger.warn(TAG, `Purchase query failed: ${this.formatError(error as Object)}`);
      }
    }
    return pending;
  }

  private deduplicate(purchases: PendingPurchase[]): PendingPurchase[] {
    const seen = new Set<string>();
    return purchases.filter((item: PendingPurchase): boolean => {
      const key = `${item.evidence.productId}:${item.evidence.purchaseToken}`;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  private evidenceFromRaw(raw: string): ProPurchaseEvidence | null {
    const payload = this.parsePurchaseData(raw);
    if (payload === null || !isKnownProProduct(payload.productId)) {
      return null;
    }
    return {
      productId: payload.productId,
      productType: productTypeForId(payload.productId),
      purchaseToken: payload.purchaseToken,
      purchaseOrderId: payload.purchaseOrderId,
      rawPurchaseData: raw
    };
  }

  private parsePurchaseData(raw: string): PurchasePayload | null {
    try {
      const value = JSON.parse(raw) as Object;
      if (value === null || typeof value !== 'object' || Array.isArray(value)) {
        return null;
      }
      return this.findPurchasePayload(value as Record<string, Object>, 0);
    } catch (error) {
      Logger.warn(TAG, `Purchase data parse failed: ${String(error)}`);
      return null;
    }
  }

  private findPurchasePayload(data: Record<string, Object>, depth: number): PurchasePayload | null {
    if (depth > 6) {
      return null;
    }
    const direct = this.normalizePurchasePayload(data);
    if (direct !== null) {
      return direct;
    }
    for (const key of Object.keys(data)) {
      const value = data[key];
      if ((key === 'jwsPurchaseOrder' || key === 'jwsSubscriptionStatus') && typeof value === 'string') {
        const decoded = this.decodeJwsPayload(value);
        if (decoded !== null) {
          const found = this.findPurchasePayload(decoded, depth + 1);
          if (found !== null) {
            return found;
          }
        }
      } else if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
        const found = this.findPurchasePayload(value as Record<string, Object>, depth + 1);
        if (found !== null) {
          return found;
        }
      }
    }
    return null;
  }

  private normalizePurchasePayload(data: Record<string, Object>): PurchasePayload | null {
    const productId = this.stringField(data['productId']);
    const purchaseToken = this.stringField(data['purchaseToken']);
    const purchaseOrderId = this.stringField(data['purchaseOrderId']) || this.stringField(data['orderId']);
    if (productId.length === 0 || purchaseToken.length === 0) {
      return null;
    }
    return { productId: productId, purchaseToken: purchaseToken, purchaseOrderId: purchaseOrderId };
  }

  private decodeJwsPayload(jws: string): Record<string, Object> | null {
    try {
      const segments = jws.split('.');
      if (segments.length < 3) {
        return null;
      }
      let normalized = segments[1].replace(/-/g, '+').replace(/_/g, '/');
      const remainder = normalized.length % 4;
      if (remainder > 0) {
        normalized += '='.repeat(4 - remainder);
      }
      const bytes = new util.Base64Helper().decodeSync(normalized);
      const parsed = JSON.parse(new util.TextDecoder().decodeToString(bytes)) as Object;
      return parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
        ? parsed as Record<string, Object> : null;
    } catch (error) {
      Logger.warn(TAG, `JWS decode failed: ${String(error)}`);
      return null;
    }
  }

  private async finishPurchase(context: common.UIAbilityContext, evidence: ProPurchaseEvidence): Promise<void> {
    if (evidence.purchaseOrderId.length === 0) {
      return;
    }
    try {
      await iap.finishPurchase(context, {
        productType: evidence.productType as iap.ProductType,
        purchaseToken: evidence.purchaseToken,
        purchaseOrderId: evidence.purchaseOrderId
      });
      Logger.info(TAG, 'Verified purchase delivery acknowledged');
    } catch (error) {
      Logger.warn(TAG, `Purchase finish deferred: ${this.formatError(error as Object)}`);
    }
  }

  private stringField(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private errorCode(error: Object): number {
    const businessError = error as BusinessError;
    return typeof businessError.code === 'number' ? businessError.code : -1;
  }

  private formatError(error: Object): string {
    const businessError = error as BusinessError;
    const code = this.errorCode(error);
    const message = businessError.message || String(error);
    return code >= 0 ? `${code} ${message}` : message;
  }
}
