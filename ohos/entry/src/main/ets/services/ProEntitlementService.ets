import preferences from '@ohos.data.preferences';

import { ProEntitlement, isActiveProEntitlement } from '../models/ProModels';
import { Logger } from '../utils/Logger';
import { ProEntitlementApiService } from './ProEntitlementApiService';

const TAG: string = 'ProEntitlement';
const STORE_NAME: string = 'zhuo_pro_entitlement';
const ENTITLEMENT_KEY: string = 'server_entitlement';
const CACHE_MAX_AGE_MS: number = 6 * 60 * 60 * 1000;

export class ProEntitlementService {
  private static instance: ProEntitlementService | null = null;
  private entitlement: ProEntitlement | null = null;

  private constructor() {}

  static getInstance(): ProEntitlementService {
    if (ProEntitlementService.instance === null) {
      ProEntitlementService.instance = new ProEntitlementService();
    }
    return ProEntitlementService.instance;
  }

  async initialize(context: Context): Promise<boolean> {
    await this.loadFreshCache(context);
    return this.refresh(context, 'app_start');
  }

  isPro(now: number = Date.now()): boolean {
    return this.isFresh(this.entitlement, now) && isActiveProEntitlement(this.entitlement, now);
  }

  current(): ProEntitlement | null {
    return this.entitlement;
  }

  async refresh(context: Context, reason: string): Promise<boolean> {
    try {
      const entitlement = await ProEntitlementApiService.getInstance().fetchEntitlements(context);
      await this.applyServerEntitlement(context, entitlement);
    } catch (error) {
      Logger.warn(TAG, `Entitlement refresh failed, reason=${reason}: ${String(error)}`);
    }
    return this.isPro();
  }

  async applyServerEntitlement(context: Context, entitlement: ProEntitlement | null): Promise<void> {
    this.entitlement = entitlement;
    const store = await preferences.getPreferences(context, STORE_NAME);
    if (entitlement === null) {
      await store.delete(ENTITLEMENT_KEY);
    } else {
      await store.put(ENTITLEMENT_KEY, JSON.stringify(entitlement));
    }
    await store.flush();
  }

  private async loadFreshCache(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(ENTITLEMENT_KEY, '') as string;
      if (raw.length === 0) {
        return;
      }
      const cached = JSON.parse(raw) as ProEntitlement;
      if (this.isFresh(cached, Date.now())) {
        this.entitlement = cached;
      }
    } catch (error) {
      Logger.warn(TAG, `Invalid entitlement cache: ${String(error)}`);
      this.entitlement = null;
    }
  }

  private isFresh(entitlement: ProEntitlement | null, now: number): boolean {
    return entitlement !== null && entitlement.verifiedAt > 0 &&
      now - entitlement.verifiedAt <= CACHE_MAX_AGE_MS;
  }
}
