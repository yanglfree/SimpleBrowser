import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { SiteControl, cloneSiteControl, defaultSiteControl, hasSiteControlOverride } from '../models/SiteControlModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'SiteControlRepository';
const STORE_NAME: string = 'zhuoyue_site_controls';
const CONTROLS_KEY: string = 'site_controls';

/** Persists only compact per-host preferences; page activity is intentionally stored elsewhere in memory. */
export class SiteControlRepository {
  private store: preferences.Preferences | undefined;
  private controls: SiteControl[] = [];

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const value: preferences.ValueType = await this.store.get(CONTROLS_KEY, '[]');
      this.controls = this.decode(typeof value === 'string' ? value : '[]');
    } catch (error) {
      this.store = undefined;
      this.controls = [];
      Logger.error(TAG, `Failed to initialize site controls: ${String(error)}`);
    }
  }

  get(host: string): SiteControl {
    const control: SiteControl | undefined = this.controls.find((item: SiteControl): boolean => item.host === host);
    return control === undefined ? defaultSiteControl(host) : cloneSiteControl(control);
  }

  async save(control: SiteControl): Promise<void> {
    const host: string = control.host.toLowerCase();
    if (host.length === 0) {
      return;
    }
    const normalized: SiteControl = cloneSiteControl(control);
    normalized.host = host;
    const remaining: SiteControl[] = this.controls.filter((item: SiteControl): boolean => item.host !== host);
    this.controls = hasSiteControlOverride(normalized) ? remaining.concat([normalized]) : remaining;
    if (this.store === undefined) {
      throw new Error('Site control storage is not initialized');
    }
    await this.store.put(CONTROLS_KEY, JSON.stringify(this.controls));
    await this.store.flush();
  }

  private decode(value: string): SiteControl[] {
    try {
      const parsed: SiteControl[] = JSON.parse(value) as SiteControl[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((item: SiteControl): boolean =>
          item !== undefined && typeof item.host === 'string' && item.host.length > 0)
        .map((item: SiteControl): SiteControl => ({
          host: item.host.toLowerCase(),
          networkBlocking: item.networkBlocking ?? 0,
          trackerBlocking: item.trackerBlocking ?? 0,
          cosmeticCleanup: item.cosmeticCleanup ?? 0,
          autoReader: item.autoReader ?? 0,
          darkMode: item.darkMode ?? 0,
          desktopUserAgent: item.desktopUserAgent ?? 0
        }));
    } catch (error) {
      Logger.warn(TAG, `Ignoring invalid site controls: ${String(error)}`);
      return [];
    }
  }
}
