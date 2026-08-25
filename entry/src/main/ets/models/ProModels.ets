export enum ProPlan {
  MONTHLY = 'monthly',
  YEARLY = 'yearly',
  LIFETIME = 'lifetime'
}

export enum ProFeature {
  ARTICLE_LIBRARY = 'article_library',
  OFFLINE_ARTICLE = 'offline_article',
  ARTICLE_EXPORT = 'article_export',
  ARTICLE_ANNOTATION = 'article_annotation',
  ARTICLE_WORKBENCH = 'article_workbench'
}

export const PRO_MONTHLY_PRODUCT_ID: string = 'com.youdroid.zhuobrowser.pro_monthly';
export const PRO_YEARLY_PRODUCT_ID: string = 'com.youdroid.zhuobrowser.pro_yearly';
export const PRO_LIFETIME_PRODUCT_ID: string = 'com.youdroid.zhuobrowser.pro_lifetime';
export const SUBSCRIPTION_PRODUCT_TYPE: number = 2;
export const NON_CONSUMABLE_PRODUCT_TYPE: number = 1;

export const SUBSCRIPTION_PRODUCT_IDS: string[] = [
  PRO_MONTHLY_PRODUCT_ID,
  PRO_YEARLY_PRODUCT_ID
];
export const LIFETIME_PRODUCT_IDS: string[] = [PRO_LIFETIME_PRODUCT_ID];

export interface ProEntitlement {
  active: boolean;
  scope: string;
  plan: ProPlan | null;
  productId: string;
  expiresAt: number;
  source: string;
  verifiedAt: number;
}

export interface ProPurchaseEvidence {
  productId: string;
  productType: number;
  purchaseToken: string;
  purchaseOrderId: string;
  rawPurchaseData: string;
}

export interface ProVerifyResult {
  verified: boolean;
  entitlement: ProEntitlement | null;
  needsFinishTransaction: boolean;
  message: string;
}

export function isKnownProProduct(productId: string): boolean {
  return SUBSCRIPTION_PRODUCT_IDS.includes(productId) || productId === PRO_LIFETIME_PRODUCT_ID;
}

export function productTypeForId(productId: string): number {
  return productId === PRO_LIFETIME_PRODUCT_ID ? NON_CONSUMABLE_PRODUCT_TYPE : SUBSCRIPTION_PRODUCT_TYPE;
}

export function isActiveProEntitlement(entitlement: ProEntitlement | null, now: number = Date.now()): boolean {
  if (entitlement === null || !entitlement.active || entitlement.scope !== 'pro') {
    return false;
  }
  return entitlement.expiresAt <= 0 || entitlement.expiresAt > now;
}
