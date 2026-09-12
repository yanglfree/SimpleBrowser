import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import preferences from '@ohos.data.preferences'
import hilog from '@ohos.hilog'
import {
  ProEntitlement,
  ProPlan,
  ProPurchaseEvidence,
  ProVerifyResult,
  PRO_LIFETIME_PRODUCT_ID,
  PRO_MONTHLY_PRODUCT_ID,
  PRO_YEARLY_PRODUCT_ID
} from '../models/ProModels'

const TAG = 'ProEntitlementApi'
const APP_ID = 'zhuobrowser'
const PLATFORM = 'harmony'
const PREF_STORE_NAME = 'zhuo_iap_identity'
const PREF_KEY_INSTALL_ID = 'install_id'
const IAP_API_BASE_URLS: string[] = [
  'https://gateway.youdroid.top'
]

interface IapEvidencePayload {
  store_product_id: string
  product_type: number
  purchase_token: string
  purchase_order_id: string
  raw_purchase_data: string
  idempotency_key: string
}

interface IapVerifyRequestBody extends IapEvidencePayload {
  platform: string
  app_id: string
  account_id: string
  client_event_time: number
  reason: string
}

interface IapRestoreRequestBody {
  platform: string
  app_id: string
  account_id: string
  purchases: IapEvidencePayload[]
  client_event_time: number
  reason: string
}

export class ProEntitlementApiService {
  private static instance: ProEntitlementApiService | null = null
  private readonly connectTimeoutMs: number = 6000
  private readonly readTimeoutMs: number = 12000

  private constructor() {}

  static getInstance(): ProEntitlementApiService {
    if (!ProEntitlementApiService.instance) {
      ProEntitlementApiService.instance = new ProEntitlementApiService()
    }
    return ProEntitlementApiService.instance
  }

  async verifyHarmonyPurchase(
    context: Context,
    evidence: ProPurchaseEvidence,
    reason: string
  ): Promise<ProVerifyResult> {
    const accountId = await this.getInstallId(context)
    const requestBody: IapVerifyRequestBody = {
      platform: PLATFORM,
      app_id: APP_ID,
      account_id: accountId,
      store_product_id: evidence.productId,
      product_type: evidence.productType,
      purchase_token: evidence.purchaseToken,
      purchase_order_id: evidence.purchaseOrderId,
      raw_purchase_data: evidence.rawPurchaseData,
      idempotency_key: this.buildIdempotencyKey(evidence),
      client_event_time: Date.now(),
      reason: reason
    }
    const payload = await this.postJson('/verify', requestBody)
    return this.parseVerifyResult(payload)
  }

  async restoreHarmonyPurchases(
    context: Context,
    evidences: ProPurchaseEvidence[],
    reason: string
  ): Promise<ProEntitlement | null> {
    const accountId = await this.getInstallId(context)
    const purchases = evidences.map((evidence: ProPurchaseEvidence) => this.buildEvidencePayload(evidence))
    const requestBody: IapRestoreRequestBody = {
      platform: PLATFORM,
      app_id: APP_ID,
      account_id: accountId,
      purchases: purchases,
      client_event_time: Date.now(),
      reason: reason
    }
    const payload = await this.postJson('/restore', requestBody)
    return this.parseEntitlement(payload['entitlement'])
  }

  async fetchEntitlements(context: Context): Promise<ProEntitlement | null> {
    const accountId = await this.getInstallId(context)
    const payload = await this.requestIapJson(
      `/entitlements?platform=${PLATFORM}&app_id=${APP_ID}&account_id=${accountId}`,
      http.RequestMethod.GET
    )
    return this.parseEntitlement(payload['entitlement'])
  }

  async getAccountId(context: Context): Promise<string> {
    return this.getInstallId(context)
  }

  private async getInstallId(context: Context): Promise<string> {
    const store = await preferences.getPreferences(context, PREF_STORE_NAME)
    const cached = await store.get(PREF_KEY_INSTALL_ID, '') as string
    if (cached.length > 0) {
      return cached
    }

    const installId = `zb-${Date.now().toString(36)}-${Math.floor(Math.random() * 1000000000000).toString(36)}`
    await store.put(PREF_KEY_INSTALL_ID, installId)
    await store.flush()
    return installId
  }

  private buildEvidencePayload(evidence: ProPurchaseEvidence): IapEvidencePayload {
    return {
      store_product_id: evidence.productId,
      product_type: evidence.productType,
      purchase_token: evidence.purchaseToken,
      purchase_order_id: evidence.purchaseOrderId,
      raw_purchase_data: evidence.rawPurchaseData,
      idempotency_key: this.buildIdempotencyKey(evidence)
    }
  }

  private buildIdempotencyKey(evidence: ProPurchaseEvidence): string {
    const stablePurchaseId = evidence.purchaseOrderId.length > 0 ? evidence.purchaseOrderId : evidence.purchaseToken
    return `${PLATFORM}:${APP_ID}:${evidence.productId}:${stablePurchaseId}`
  }

  private async postJson(path: string, body: Object): Promise<Record<string, Object>> {
    return await this.requestIapJson(path, http.RequestMethod.POST, body)
  }

  private async requestIapJson(
    path: string,
    method: http.RequestMethod,
    body?: Object
  ): Promise<Record<string, Object>> {
    const baseUrls = this.resolveBaseUrls()
    let lastError: Object | null = null

    for (let index = 0; index < baseUrls.length; index++) {
      const baseUrl = baseUrls[index]
      try {
        return await this.requestJson(this.buildUrl(baseUrl, path), method, body)
      } catch (err) {
        lastError = err as Object
        const canRetry = index < baseUrls.length - 1
        const message =
          `IAP API request failed at ${this.hostLabel(baseUrl)}: ${this.formatError(err as Object)}`
        if (canRetry) {
          hilog.warn(0x0000, TAG, `${message}; retrying fallback endpoint`)
        } else {
          hilog.error(0x0000, TAG, message)
        }
      }
    }

    if (lastError) {
      throw new Error(this.userFacingError(lastError))
    }
    throw new Error('IAP_API_ENDPOINT_UNAVAILABLE')
  }

  private async requestJson(
    url: string,
    method: http.RequestMethod,
    body?: Object
  ): Promise<Record<string, Object>> {
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(
        url,
        {
          method: method,
          header: {
            'Content-Type': 'application/json',
            'X-App-Id': APP_ID,
            'X-Platform': 'HarmonyOS'
          },
          extraData: body ? JSON.stringify(body) : '',
          expectDataType: http.HttpDataType.OBJECT,
          readTimeout: this.readTimeoutMs,
          connectTimeout: this.connectTimeoutMs
        }
      )

      const payload = this.normalizeObject(response.result)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const code = payload ? this.toStringField(payload['code']) : ''
        hilog.error(0x0000, TAG, `IAP server request failed: status=${response.responseCode}, code=${code}`)
        throw new Error(`IAP_SERVER_${response.responseCode}`)
      }
      if (!payload) {
        throw new Error('IAP_SERVER_INVALID_RESPONSE')
      }
      return payload
    } finally {
      httpRequest.destroy()
    }
  }

  private buildUrl(baseUrl: string, path: string): string {
    return `${baseUrl}/v1/iap${path}`
  }

  private resolveBaseUrls(): string[] {
    const urls: string[] = []
    const seen = new Set<string>()
    for (const url of IAP_API_BASE_URLS) {
      const baseUrl = url.replace(/\/$/, '')
      if (!baseUrl.startsWith('https://')) {
        continue
      }
      if (seen.has(baseUrl)) {
        continue
      }
      seen.add(baseUrl)
      urls.push(baseUrl)
    }
    if (urls.length > 0) {
      return urls
    }
    return ['https://gateway.youdroid.top']
  }

  private hostLabel(baseUrl: string): string {
    const withoutScheme = baseUrl.replace(/^https?:\/\//, '')
    const pathIndex = withoutScheme.indexOf('/')
    return pathIndex >= 0 ? withoutScheme.substring(0, pathIndex) : withoutScheme
  }

  private formatError(err: Object): string {
    const bizErr = err as BusinessError
    const code = typeof bizErr.code === 'number' ? bizErr.code : -1
    const message = bizErr.message || ''
    if (code >= 0 && message.length > 0) {
      return `${code} ${message}`
    }
    if (code >= 0) {
      return `${code}`
    }
    if (message.length > 0) {
      return message
    }
    try {
      const serialized = JSON.stringify(err)
      if (serialized && serialized !== '{}') {
        return serialized
      }
    } catch (jsonErr) {
      return `${jsonErr}`
    }
    const raw = `${err}`
    return raw === '[object Object]' ? 'unknown error' : raw
  }

  private userFacingError(err: Object): string {
    const bizErr = err as BusinessError
    const code = typeof bizErr.code === 'number' ? bizErr.code : -1
    const message = bizErr.message || ''
    if (code >= 0 && message.length > 0) {
      return `[${code}] ${message}`
    }
    return this.formatError(err)
  }

  private parseVerifyResult(payload: Record<string, Object>): ProVerifyResult {
    return {
      verified: this.toBooleanField(payload['verified']),
      entitlement: this.parseEntitlement(payload['entitlement']),
      needsFinishTransaction: this.toBooleanField(payload['needs_finish_transaction'], true),
      message: this.toStringField(payload['message'])
    }
  }

  private parseEntitlement(value: Object | undefined): ProEntitlement | null {
    const payload = this.normalizeObject(value)
    if (!payload) {
      return null
    }

    const productId = this.toStringField(payload['product_id'])
    const plan = this.resolvePlan(this.toStringField(payload['plan']), productId)
    return {
      active: this.toBooleanField(payload['active']),
      scope: this.toStringField(payload['scope']),
      plan: plan,
      productId: productId,
      expiresAt: this.toNumberField(payload['expires_at']),
      source: this.toStringField(payload['source']) || 'server',
      verifiedAt: this.toNumberField(payload['verified_at'])
    }
  }

  private normalizeObject(value: Object | undefined): Record<string, Object> | null {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, Object>
    }
    return null
  }

  private resolvePlan(plan: string, productId: string): ProPlan | null {
    if (plan === ProPlan.MONTHLY || productId === PRO_MONTHLY_PRODUCT_ID) {
      return ProPlan.MONTHLY
    }
    if (plan === ProPlan.YEARLY || productId === PRO_YEARLY_PRODUCT_ID) {
      return ProPlan.YEARLY
    }
    if (plan === ProPlan.LIFETIME || productId === PRO_LIFETIME_PRODUCT_ID) {
      return ProPlan.LIFETIME
    }
    return null
  }

  private toStringField(value: Object | undefined): string {
    if (typeof value === 'string') {
      return value
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return `${value}`
    }
    return ''
  }

  private toNumberField(value: Object | undefined): number {
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'string' && value.length > 0) {
      const parsed = Number(value)
      if (parsed === parsed) {
        return parsed
      }
    }
    return 0
  }

  private toBooleanField(value: Object | undefined, fallback: boolean = false): boolean {
    if (typeof value === 'boolean') {
      return value
    }
    if (typeof value === 'string') {
      return value === 'true'
    }
    if (typeof value === 'number') {
      return value !== 0
    }
    return fallback
  }
}
