import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserSettings,
  cloneSettings,
  defaultBrowserSettings,
  normalizeBrowserSettings
} from '../main/ets/models/BrowserModels';
import {
  DEFAULT_LANDSCAPE_PRESET_ID,
  DEFAULT_PORTRAIT_PRESET_ID,
  getAvailablePresets,
  HomeBackgroundPreset,
  LANDSCAPE_PRESETS,
  PORTRAIT_PRESETS,
  resolvePresetResource
} from '../main/ets/models/HomeBackgroundPresets';
import {
  isDailyWallpaperCacheFresh,
  isSupportedDailyWallpaper,
  resolveBingDailyImageUrl
} from '../main/ets/models/BingDailyWallpaper';

export default function homeBackgroundPresetsTest(): void {
  describe('HomeBackgroundPresets filtering and resolution', (): void => {
    it('returns only landscape presets when device is in landscape mode', 0, (): void => {
      const presetsSmallScreen: HomeBackgroundPreset[] = getAvailablePresets(true, true);
      const presetsLargeScreen: HomeBackgroundPreset[] = getAvailablePresets(true, false);

      expect(presetsSmallScreen.length).assertEqual(LANDSCAPE_PRESETS.length);
      expect(presetsLargeScreen.length).assertEqual(LANDSCAPE_PRESETS.length);

      for (let i = 0; i < presetsSmallScreen.length; i += 1) {
        expect(presetsSmallScreen[i].isLandscape).assertTrue();
      }
      for (let i = 0; i < presetsLargeScreen.length; i += 1) {
        expect(presetsLargeScreen[i].isLandscape).assertTrue();
      }
    });

    it('includes legacy background on phone / small screen in portrait mode', 0, (): void => {
      const presets: HomeBackgroundPreset[] = getAvailablePresets(false, true);

      expect(presets.length).assertEqual(PORTRAIT_PRESETS.length);
      const hasRiver: boolean = presets.some((p: HomeBackgroundPreset): boolean => p.id === 'river');
      expect(hasRiver).assertTrue();

      for (let i = 0; i < presets.length; i += 1) {
        expect(presets[i].isLandscape).assertFalse();
      }
    });

    it('excludes legacy low-res background on large screen in portrait mode', 0, (): void => {
      const presets: HomeBackgroundPreset[] = getAvailablePresets(false, false);

      expect(presets.length).assertEqual(PORTRAIT_PRESETS.length - 1);
      const hasRiver: boolean = presets.some((p: HomeBackgroundPreset): boolean => p.id === 'river');
      expect(hasRiver).assertFalse();

      for (let i = 0; i < presets.length; i += 1) {
        expect(presets[i].isLandscape).assertFalse();
        expect(presets[i].smallScreenOnly !== true).assertTrue();
      }
    });

    it('resolves default landscape preset when presetId is empty or invalid', 0, (): void => {
      const defaultRes: Resource = resolvePresetResource(true, DEFAULT_LANDSCAPE_PRESET_ID);
      const fallbackFromEmpty: Resource = resolvePresetResource(true, '');
      const fallbackFromInvalid: Resource = resolvePresetResource(true, 'non_existent_preset');

      expect(defaultRes).assertDeepEquals(fallbackFromEmpty);
      expect(defaultRes).assertDeepEquals(fallbackFromInvalid);
    });

    it('resolves default portrait preset when presetId is empty or invalid', 0, (): void => {
      const defaultRes: Resource = resolvePresetResource(false, DEFAULT_PORTRAIT_PRESET_ID);
      const fallbackFromEmpty: Resource = resolvePresetResource(false, '');
      const fallbackFromInvalid: Resource = resolvePresetResource(false, 'non_existent_preset');

      expect(defaultRes).assertDeepEquals(fallbackFromEmpty);
      expect(defaultRes).assertDeepEquals(fallbackFromInvalid);
    });

    it('resolves specific landscape and portrait presets by valid id', 0, (): void => {
      const archRes: Resource = resolvePresetResource(true, 'arch');
      const roofRes: Resource = resolvePresetResource(true, 'roof');
      expect(archRes).not().assertDeepEquals(roofRes);

      const mountainRes: Resource = resolvePresetResource(false, 'mountain');
      const alleyRes: Resource = resolvePresetResource(false, 'alley');
      expect(mountainRes).not().assertDeepEquals(alleyRes);
    });

    it('preserves preset IDs across settings cloning and normalization', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();
      expect(settings.startPagePresetPortraitId).assertEqual(DEFAULT_PORTRAIT_PRESET_ID);
      expect(settings.startPagePresetLandscapeId).assertEqual(DEFAULT_LANDSCAPE_PRESET_ID);

      settings.startPagePresetPortraitId = 'alley';
      settings.startPagePresetLandscapeId = 'roof';

      const cloned: BrowserSettings = cloneSettings(settings);
      expect(cloned.startPagePresetPortraitId).assertEqual('alley');
      expect(cloned.startPagePresetLandscapeId).assertEqual('roof');

      const normalized: BrowserSettings = normalizeBrowserSettings(settings);
      expect(normalized.startPagePresetPortraitId).assertEqual('alley');
      expect(normalized.startPagePresetLandscapeId).assertEqual('roof');
    });

    it('accepts only Bing image paths from the daily archive response', 0, (): void => {
      const valid: string = '{"images":[{"url":"/th?id=OHR.Sample_ZH-CN123_1920x1080.jpg&pid=hp"}]}';
      const external: string = '{"images":[{"url":"https://example.com/wallpaper.jpg"}]}';

      expect(resolveBingDailyImageUrl(valid))
        .assertEqual('https://www.bing.com/th?id=OHR.Sample_ZH-CN123_1920x1080.jpg&pid=hp');
      expect(resolveBingDailyImageUrl(external)).assertUndefined();
      expect(resolveBingDailyImageUrl('{invalid')).assertUndefined();
    });

    it('refreshes the daily wallpaper once per local calendar day', 0, (): void => {
      const morning: number = new Date(2026, 8, 6, 8, 0, 0).getTime();
      const evening: number = new Date(2026, 8, 6, 20, 0, 0).getTime();
      const nextDay: number = new Date(2026, 8, 7, 8, 0, 0).getTime();

      expect(isDailyWallpaperCacheFresh(morning, evening)).assertTrue();
      expect(isDailyWallpaperCacheFresh(morning, nextDay)).assertFalse();
    });

    it('rejects non-JPEG responses before caching a daily wallpaper', 0, (): void => {
      expect(isSupportedDailyWallpaper(new Uint8Array([0xFF, 0xD8, 0xFF, 0xD9]))).assertTrue();
      expect(isSupportedDailyWallpaper(new Uint8Array([0x7B, 0x7D, 0x00, 0x00]))).assertFalse();
    });
  });
}
