import { common } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { http } from '@kit.NetworkKit';
import { asset } from '@kit.AssetStoreKit';
import preferences from '@ohos.data.preferences';
import {
  AccountUserProfile,
  AuthProviderKind,
  LinkedIdentityItem
} from '../models/AccountSyncModels';
import {
  PRO_LIFETIME_PRODUCT_ID,
  PRO_MONTHLY_PRODUCT_ID,
  PRO_YEARLY_PRODUCT_ID,
  ProEntitlement,
  ProPlan
} from '../models/ProModels';
import { Logger } from '../utils/Logger';
import { ProEntitlementApiService } from './ProEntitlementApiService';
import { isGoogleSignInAvailable, resolveHarmonyAuthProviders } from './RegionAuthPolicy';

const TAG: string = 'AccountAuthService';
const PRIMARY_AUTH_BASE_URL: string = 'https://auth.zhuobrowser.youdroid.top';
const FALLBACK_AUTH_BASE_URL: string = 'https://zhuobrowser-auth-service.memoryphoto.workers.dev';
const STORE_NAME: string = 'zhuo_account_store';
const TOKEN_KEY: string = 'account_token';
const PROFILE_KEY: string = 'account_profile';
const IDENTITIES_KEY: string = 'account_identities';
const DEVICE_ID_KEY: string = 'account_device_id';
const LAST_SYNC_KEY: string = 'account_last_sync';
const ASSET_ALIAS: string = 'zhuobrowser_auth_token_v1';

interface HttpJsonResponse {
  status: number;
  payload: Record<string, Object>;
}

interface OtpSendRequestBody {
  email: string;
}

interface OtpVerifyRequestBody {
  email: string;
  code: string;
  displayName: string;
  deviceId: string;
  deviceName: string;
  platform: string;
}

interface PasswordLoginRequestBody {
  email: string;
  password: string;
  deviceId: string;
  deviceName: string;
  platform: string;
}

interface PasswordRegisterRequestBody {
  email: string;
  password: string;
  displayName: string;
  deviceId: string;
  deviceName: string;
  platform: string;
}

interface HuaweiNativeOAuthRequestBody {
  provider: string;
  idToken: string;
  authorizationCode: string;
  deviceId: string;
  deviceName: string;
  platform: string;
}

interface OAuthExchangeRequestBody {
  ticket: string;
}

interface ProBindRequestBody {
  platform: string;
  installId: string;
}

export class AccountAuthService {
  private static instance: AccountAuthService | null = null;
  private token: string = '';
  private currentUser: AccountUserProfile | null = null;
  private linkedIdentities: LinkedIdentityItem[] = [];
  private cloudProEntitlement: ProEntitlement | null = null;
  private lastSyncTime: number = 0;
  private deviceId: string = '';
  private initialized: boolean = false;
  lastError: string = '';

  private constructor() {}

  static getInstance(): AccountAuthService {
    if (AccountAuthService.instance === null) {
      AccountAuthService.instance = new AccountAuthService();
    }
    return AccountAuthService.instance;
  }

  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const savedDeviceId: string = await store.get(DEVICE_ID_KEY, '') as string;
      if (savedDeviceId.length > 0) {
        this.deviceId = savedDeviceId;
      } else {
        this.deviceId = `ohos-${Date.now().toString(36)}-${Math.floor(Math.random() * 1000000).toString(36)}`;
        await store.put(DEVICE_ID_KEY, this.deviceId);
        await store.flush();
      }
      const rawProfile: string = await store.get(PROFILE_KEY, '') as string;
      if (rawProfile.length > 0) {
        this.currentUser = JSON.parse(rawProfile) as AccountUserProfile;
      }
      const rawIdentities: string = await store.get(IDENTITIES_KEY, '') as string;
      if (rawIdentities.length > 0) {
        this.linkedIdentities = JSON.parse(rawIdentities) as LinkedIdentityItem[];
      }
      this.lastSyncTime = await store.get(LAST_SYNC_KEY, 0) as number;
      let loadedToken: string = await this.readTokenFromAsset();
      if (loadedToken.length === 0) {
        loadedToken = await store.get(TOKEN_KEY, '') as string;
      }
      this.token = loadedToken;
    } catch (error) {
      Logger.warn(TAG, `Failed to restore account store: ${String(error)}`);
    }
  }

  isLoggedIn(): boolean {
    return this.token.length > 0 && this.currentUser !== null;
  }

  getToken(): string {
    return this.token;
  }

  getDeviceId(): string {
    return this.deviceId.length > 0 ? this.deviceId : 'ohos-default';
  }

  getDeviceName(): string {
    const model: string = deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS Device';
    return model;
  }

  getCurrentUser(): AccountUserProfile | null {
    return this.currentUser;
  }

  getLinkedIdentities(): LinkedIdentityItem[] {
    return this.linkedIdentities.slice(0);
  }

  getCloudProEntitlement(): ProEntitlement | null {
    return this.cloudProEntitlement;
  }

  getLastSyncTime(): number {
    return this.lastSyncTime;
  }

  async setLastSyncTime(context: Context, timestamp: number): Promise<void> {
    this.lastSyncTime = timestamp;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(LAST_SYNC_KEY, timestamp);
      await store.flush();
    } catch (error) {
      Logger.warn(TAG, `Failed to persist lastSyncTime: ${String(error)}`);
    }
  }

  getSystemRegionCode(): string {
    try {
      return i18n.System.getSystemRegion();
    } catch (_err) {
      return '';
    }
  }

  getSystemTimezone(): string {
    try {
      return i18n.getTimeZone().getID();
    } catch (_err) {
      return '';
    }
  }

  isGoogleSignInAvailableForDevice(): boolean {
    return isGoogleSignInAvailable(this.getSystemRegionCode(), this.getSystemTimezone());
  }

  getAvailableProviders(): AuthProviderKind[] {
    return resolveHarmonyAuthProviders(this.getSystemRegionCode(), this.getSystemTimezone());
  }

  buildGoogleOAuthStartUrl(): string {
    if (!this.isGoogleSignInAvailableForDevice()) {
      return '';
    }
    const redirect: string = encodeURIComponent('zhuobrowser-auth://oauth/callback');
    return `${PRIMARY_AUTH_BASE_URL}/api/auth/oauth/google/start?platform=harmony&client_redirect_uri=${redirect}`;
  }

  async sendEmailOtp(email: string): Promise<boolean> {
    this.lastError = '';
    const cleaned: string = email.trim();
    if (cleaned.length === 0) {
      this.lastError = '请输入邮箱地址';
      return false;
    }
    try {
      const payload: OtpSendRequestBody = {
        email: cleaned
      };
      const res: HttpJsonResponse = await this.requestJson('/api/auth/otp/send', http.RequestMethod.POST, payload);
      if (res.status === 200) {
        return true;
      }
      this.lastError = this.stringField(res.payload['error']) || '验证码发送失败';
    } catch (error) {
      this.lastError = String(error);
    }
    return false;
  }

  async verifyEmailOtp(context: Context, email: string, code: string, displayName: string = ''): Promise<boolean> {
    const payload: OtpVerifyRequestBody = {
      email: email.trim(),
      code: code.trim(),
      displayName: displayName.trim(),
      deviceId: this.getDeviceId(),
      deviceName: this.getDeviceName(),
      platform: 'harmony'
    };
    return await this.performAuthPost(context, '/api/auth/otp/verify', payload);
  }

  async loginWithPassword(context: Context, email: string, password: string): Promise<boolean> {
    const payload: PasswordLoginRequestBody = {
      email: email.trim(),
      password: password,
      deviceId: this.getDeviceId(),
      deviceName: this.getDeviceName(),
      platform: 'harmony'
    };
    return await this.performAuthPost(context, '/api/auth/login', payload);
  }

  async registerWithPassword(context: Context, email: string, password: string, displayName: string): Promise<boolean> {
    const payload: PasswordRegisterRequestBody = {
      email: email.trim(),
      password: password,
      displayName: displayName.trim(),
      deviceId: this.getDeviceId(),
      deviceName: this.getDeviceName(),
      platform: 'harmony'
    };
    return await this.performAuthPost(context, '/api/auth/register', payload);
  }

  async signInWithHuawei(context: common.UIAbilityContext): Promise<boolean> {
    this.lastError = '';
    try {
      const loginRequest: authentication.LoginWithHuaweiIDRequest =
        new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      loginRequest.forceLogin = true;
      loginRequest.idTokenSignAlgorithm = authentication.IdTokenSignAlgorithm.RS256;
      const controller: authentication.AuthenticationController = new authentication.AuthenticationController(context);
      const response: authentication.LoginWithHuaweiIDResponse =
        await controller.executeRequest(loginRequest) as authentication.LoginWithHuaweiIDResponse;
      const idToken: string = response.data?.idToken ?? '';
      const authCode: string = response.data?.authorizationCode ?? '';
      if (idToken.length === 0 && authCode.length === 0) {
        this.lastError = '华为账号未返回有效授权凭据';
        return false;
      }
      const payload: HuaweiNativeOAuthRequestBody = {
        provider: 'huawei',
        idToken: idToken,
        authorizationCode: authCode,
        deviceId: this.getDeviceId(),
        deviceName: this.getDeviceName(),
        platform: 'harmony'
      };
      return await this.performAuthPost(context, '/api/auth/oauth/native', payload, this.token);
    } catch (error) {
      this.lastError = `华为账号登录不可用：${String(error)}`;
      return false;
    }
  }

  async completeOAuthCallbackUrl(context: Context, callbackUrl: string): Promise<boolean> {
    const queryIdx: number = callbackUrl.indexOf('?');
    if (queryIdx < 0) {
      return false;
    }
    const query: string = callbackUrl.substring(queryIdx + 1);
    const parts: string[] = query.split('&');
    let ticket: string = '';
    for (let i = 0; i < parts.length; i++) {
      const kv: string[] = parts[i].split('=');
      if (kv.length === 2 && kv[0] === 'ticket') {
        ticket = decodeURIComponent(kv[1]);
        break;
      }
    }
    if (ticket.length === 0) {
      return false;
    }
    const payload: OAuthExchangeRequestBody = {
      ticket: ticket
    };
    return await this.performAuthPost(context, '/api/auth/oauth/exchange', payload);
  }

  async refreshMe(context: Context): Promise<void> {
    if (this.token.length === 0) {
      return;
    }
    try {
      const res: HttpJsonResponse = await this.requestJson(
        '/api/auth/me',
        http.RequestMethod.GET,
        undefined,
        this.token
      );
      if (res.status === 200) {
        const userObj: Record<string, Object> | null = this.objectField(res.payload['user']);
        if (userObj !== null) {
          const profile: AccountUserProfile | null = this.parseProfile(userObj);
          if (profile !== null) {
            this.currentUser = profile;
            this.linkedIdentities = this.parseIdentities(res.payload['identities']);
            await this.persistSession(context, this.token, profile, this.linkedIdentities);
            await this.bindCurrentInstallForPro(context);
            await this.fetchCloudProEntitlement();
          }
        }
      } else if (res.status === 401 || res.status === 403) {
        await this.clearLocalSession(context);
      }
    } catch (_err) {
      // Keep offline login state
    }
  }

  async bindCurrentInstallForPro(context: Context): Promise<void> {
    if (this.token.length === 0) {
      return;
    }
    try {
      const installId: string = await ProEntitlementApiService.getInstance().getAccountId(context);
      const payload: ProBindRequestBody = {
        platform: 'harmony',
        installId: installId
      };
      await this.requestJson('/api/pro/bind', http.RequestMethod.POST, payload, this.token);
    } catch (error) {
      Logger.warn(TAG, `Failed to bind Pro install ID: ${String(error)}`);
    }
  }

  async fetchCloudProEntitlement(): Promise<ProEntitlement | null> {
    if (this.token.length === 0) {
      return null;
    }
    try {
      const res: HttpJsonResponse = await this.requestJson(
        '/api/pro/entitlement',
        http.RequestMethod.GET,
        undefined,
        this.token
      );
      if (res.status !== 200) {
        return null;
      }
      const entObj: Record<string, Object> | null = this.objectField(res.payload['entitlement']);
      if (entObj === null || !this.boolField(entObj['active'])) {
        this.cloudProEntitlement = null;
        return null;
      }
      const productId: string = this.stringField(entObj['productId']) || PRO_YEARLY_PRODUCT_ID;
      const planStr: string = this.stringField(entObj['plan']);
      let plan: ProPlan = ProPlan.YEARLY;
      if (planStr === ProPlan.MONTHLY || productId === PRO_MONTHLY_PRODUCT_ID) {
        plan = ProPlan.MONTHLY;
      } else if (planStr === ProPlan.LIFETIME || productId === PRO_LIFETIME_PRODUCT_ID) {
        plan = ProPlan.LIFETIME;
      }
      const ent: ProEntitlement = {
        active: true,
        scope: this.stringField(entObj['scope']) || 'pro',
        plan: plan,
        productId: productId,
        expiresAt: this.numberField(entObj['expiresAt']),
        source: this.stringField(entObj['source']) || 'cloud_sync',
        verifiedAt: this.numberField(entObj['verifiedAt']) || Date.now()
      };
      this.cloudProEntitlement = ent;
      return ent;
    } catch (_err) {
      return null;
    }
  }

  async logout(context: Context): Promise<void> {
    if (this.token.length > 0) {
      try {
        await this.requestJson('/api/auth/logout', http.RequestMethod.POST, undefined, this.token);
      } catch (_err) {
        // Ignore network errors during logout
      }
    }
    await this.clearLocalSession(context);
  }

  async deleteAccount(context: Context): Promise<boolean> {
    this.lastError = '';
    if (this.token.length === 0) {
      return false;
    }
    try {
      const res: HttpJsonResponse = await this.requestJson(
        '/api/auth/account',
        http.RequestMethod.DELETE,
        undefined,
        this.token
      );
      if (res.status === 200 || res.status === 401 || res.status === 404) {
        await this.clearLocalSession(context);
        return true;
      }
      this.lastError = this.stringField(res.payload['error']) || '账号注销失败';
    } catch (error) {
      this.lastError = String(error);
    }
    return false;
  }

  async requestJson(
    path: string,
    method: http.RequestMethod,
    body?: Object,
    bearerToken?: string
  ): Promise<HttpJsonResponse> {
    const bases: string[] = [PRIMARY_AUTH_BASE_URL, FALLBACK_AUTH_BASE_URL];
    let lastErr: string = 'network_unavailable';
    for (let i = 0; i < bases.length; i++) {
      const url: string = `${bases[i]}${path}`;
      const client: http.HttpRequest = http.createHttp();
      try {
        const headers: Record<string, string> = {
          'Content-Type': 'application/json'
        };
        if (bearerToken !== undefined && bearerToken.length > 0) {
          headers['Authorization'] = `Bearer ${bearerToken}`;
        }
        const response: http.HttpResponse = await client.request(url, {
          method: method,
          header: headers,
          extraData: body !== undefined ? JSON.stringify(body) : '',
          expectDataType: http.HttpDataType.OBJECT,
          connectTimeout: 6000,
          readTimeout: 15000
        });
        const normalized: Record<string, Object> = this.objectField(response.result as Object) ?? {};
        return {
          status: response.responseCode,
          payload: normalized
        };
      } catch (err) {
        lastErr = String(err);
      } finally {
        client.destroy();
      }
    }
    throw new Error(lastErr);
  }

  private async performAuthPost(
    context: Context,
    path: string,
    body: Object,
    bearerToken?: string
  ): Promise<boolean> {
    this.lastError = '';
    try {
      const res: HttpJsonResponse = await this.requestJson(path, http.RequestMethod.POST, body, bearerToken);
      if (res.status >= 200 && res.status < 300) {
        const token: string = this.stringField(res.payload['token']);
        const userObj: Record<string, Object> | null = this.objectField(res.payload['user']);
        const profile: AccountUserProfile | null = userObj !== null ? this.parseProfile(userObj) : null;
        if (token.length > 0 && profile !== null) {
          const identities: LinkedIdentityItem[] = this.parseIdentities(res.payload['identities']);
          this.token = token;
          this.currentUser = profile;
          this.linkedIdentities = identities;
          await this.persistSession(context, token, profile, identities);
          await this.bindCurrentInstallForPro(context);
          await this.fetchCloudProEntitlement();
          return true;
        }
      }
      this.lastError = this.stringField(res.payload['error']) || '认证失败，请重试';
    } catch (error) {
      this.lastError = String(error);
    }
    return false;
  }

  private async persistSession(
    context: Context,
    token: string,
    profile: AccountUserProfile,
    identities: LinkedIdentityItem[]
  ): Promise<void> {
    await this.writeTokenToAsset(token);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(TOKEN_KEY, token);
      await store.put(PROFILE_KEY, JSON.stringify(profile));
      await store.put(IDENTITIES_KEY, JSON.stringify(identities));
      await store.flush();
    } catch (error) {
      Logger.warn(TAG, `Failed to persist account store: ${String(error)}`);
    }
  }

  private async clearLocalSession(context: Context): Promise<void> {
    this.token = '';
    this.currentUser = null;
    this.linkedIdentities = [];
    this.cloudProEntitlement = null;
    await this.removeTokenFromAsset();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.delete(TOKEN_KEY);
      await store.delete(PROFILE_KEY);
      await store.delete(IDENTITIES_KEY);
      await store.flush();
    } catch (error) {
      Logger.warn(TAG, `Failed to clear account store: ${String(error)}`);
    }
  }

  private async writeTokenToAsset(token: string): Promise<void> {
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      const aliasBytes: Uint8Array = encoder.encodeInto(ASSET_ALIAS);
      const secretBytes: Uint8Array = encoder.encodeInto(token);
      const queryAttr: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      queryAttr.set(asset.Tag.ALIAS, aliasBytes);
      await asset.remove(queryAttr).catch((): void => {});
      const addAttr: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      addAttr.set(asset.Tag.ALIAS, aliasBytes);
      addAttr.set(asset.Tag.SECRET, secretBytes);
      addAttr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      await asset.add(addAttr);
    } catch (_err) {
      // Preferences fallback preserves session on devices without AssetStore support
    }
  }

  private async readTokenFromAsset(): Promise<string> {
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encoder.encodeInto(ASSET_ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: asset.AssetMap[] = await asset.query(query);
      if (result.length > 0) {
        const secret: asset.Value | undefined = result[0].get(asset.Tag.SECRET);
        if (secret instanceof Uint8Array) {
          const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
          return decoder.decodeToString(secret);
        }
      }
    } catch (_err) {
      // Ignore and fall back to preferences
    }
    return '';
  }

  private async removeTokenFromAsset(): Promise<void> {
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encoder.encodeInto(ASSET_ALIAS));
      await asset.remove(query);
    } catch (_err) {
      // Ignore
    }
  }

  private parseProfile(obj: Record<string, Object>): AccountUserProfile | null {
    const id: string = this.stringField(obj['id']);
    const email: string = this.stringField(obj['email']);
    if (id.length === 0 || email.length === 0) {
      return null;
    }
    return {
      id: id,
      email: email,
      displayName: this.stringField(obj['displayName']) || email,
      avatarUrl: this.stringField(obj['avatarUrl']),
      createdAt: this.numberField(obj['createdAt'])
    };
  }

  private parseIdentities(raw: Object | undefined): LinkedIdentityItem[] {
    if (!Array.isArray(raw)) {
      return [];
    }
    const list: LinkedIdentityItem[] = [];
    const arr: Object[] = raw as Object[];
    for (let i = 0; i < arr.length; i++) {
      const obj: Record<string, Object> | null = this.objectField(arr[i]);
      if (obj === null) {
        continue;
      }
      const provider: string = this.stringField(obj['provider']);
      if (provider.length === 0) {
        continue;
      }
      list.push({
        provider: provider,
        email: this.stringField(obj['email']),
        emailVerified: this.boolField(obj['emailVerified'])
      });
    }
    return list;
  }

  private objectField(value: Object | undefined): Record<string, Object> | null {
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, Object>;
    }
    return null;
  }

  private stringField(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private numberField(value: Object | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  }

  private boolField(value: Object | undefined): boolean {
    return typeof value === 'boolean' ? value : false;
  }
}
