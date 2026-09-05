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
  });
}
