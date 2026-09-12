import { WebDarkModePreference } from './BrowserModels';

export enum SiteControlMode {
  Inherit = 0,
  Enabled = 1,
  Disabled = 2
}

export interface SiteControl {
  host: string;
  networkBlocking: SiteControlMode;
  trackerBlocking: SiteControlMode;
  cosmeticCleanup: SiteControlMode;
  autoReader: SiteControlMode;
  darkMode: SiteControlMode;
  desktopUserAgent: SiteControlMode;
}

export interface EffectiveSiteControl {
  networkBlockingEnabled: boolean;
  trackerBlockingEnabled: boolean;
  cosmeticCleanupEnabled: boolean;
  autoReaderEnabled: boolean;
  webDarkMode: WebDarkModePreference;
  desktopUserAgentEnabled: boolean;
}

export function defaultSiteControl(host: string): SiteControl {
  return {
    host: host,
    networkBlocking: SiteControlMode.Inherit,
    trackerBlocking: SiteControlMode.Inherit,
    cosmeticCleanup: SiteControlMode.Inherit,
    autoReader: SiteControlMode.Inherit,
    darkMode: SiteControlMode.Inherit,
    desktopUserAgent: SiteControlMode.Inherit
  };
}

export function cloneSiteControl(control: SiteControl): SiteControl {
  return {
    host: control.host,
    networkBlocking: control.networkBlocking,
    trackerBlocking: control.trackerBlocking,
    cosmeticCleanup: control.cosmeticCleanup,
    autoReader: control.autoReader,
    darkMode: control.darkMode,
    desktopUserAgent: control.desktopUserAgent
  };
}

export function hasSiteControlOverride(control: SiteControl): boolean {
  return control.networkBlocking !== SiteControlMode.Inherit ||
    control.trackerBlocking !== SiteControlMode.Inherit ||
    control.cosmeticCleanup !== SiteControlMode.Inherit ||
    control.autoReader !== SiteControlMode.Inherit ||
    control.darkMode !== SiteControlMode.Inherit ||
    control.desktopUserAgent !== SiteControlMode.Inherit;
}

export function resolveSiteControl(
  control: SiteControl,
  networkBlockingDefault: boolean,
  trackerBlockingDefault: boolean,
  cosmeticCleanupDefault: boolean,
  darkModeDefault: WebDarkModePreference,
  desktopUserAgentDefault: boolean
): EffectiveSiteControl {
  return {
    networkBlockingEnabled: resolveBoolean(control.networkBlocking, networkBlockingDefault),
    trackerBlockingEnabled: resolveBoolean(control.trackerBlocking, trackerBlockingDefault),
    cosmeticCleanupEnabled: resolveBoolean(control.cosmeticCleanup, cosmeticCleanupDefault),
    autoReaderEnabled: resolveBoolean(control.autoReader, false),
    webDarkMode: control.darkMode === SiteControlMode.Enabled
      ? WebDarkModePreference.Dark
      : control.darkMode === SiteControlMode.Disabled
        ? WebDarkModePreference.Light
        : darkModeDefault,
    desktopUserAgentEnabled: resolveBoolean(control.desktopUserAgent, desktopUserAgentDefault)
  };
}

function resolveBoolean(mode: SiteControlMode, fallback: boolean): boolean {
  if (mode === SiteControlMode.Enabled) {
    return true;
  }
  if (mode === SiteControlMode.Disabled) {
    return false;
  }
  return fallback;
}
