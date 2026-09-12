export interface HomeBackgroundPreset {
  id: string;
  nameRes: Resource;
  resource: Resource;
  isLandscape: boolean;
  smallScreenOnly?: boolean;
}

export const DEFAULT_PORTRAIT_PRESET_ID: string = 'mountain';
export const DEFAULT_LANDSCAPE_PRESET_ID: string = 'arch';

export const PORTRAIT_PRESETS: HomeBackgroundPreset[] = [
  {
    id: DEFAULT_PORTRAIT_PRESET_ID,
    nameRes: $r('app.string.home_background_preset_mountain'),
    resource: $rawfile('bgs/pexels-damiendufourartiste-27961888.jpg'),
    isLandscape: false
  },
  {
    id: 'alley',
    nameRes: $r('app.string.home_background_preset_alley'),
    resource: $rawfile('bgs/pexels-ersin-1398102958-28351624.jpg'),
    isLandscape: false
  },
  {
    id: 'river',
    nameRes: $r('app.string.home_background_preset_river'),
    resource: $r('app.media.home_background'),
    isLandscape: false,
    smallScreenOnly: true
  }
];

export const LANDSCAPE_PRESETS: HomeBackgroundPreset[] = [
  {
    id: DEFAULT_LANDSCAPE_PRESET_ID,
    nameRes: $r('app.string.home_background_preset_arch'),
    resource: $rawfile('bgs/pexels-lana-154214216-38140707.jpg'),
    isLandscape: true
  },
  {
    id: 'roof',
    nameRes: $r('app.string.home_background_preset_roof'),
    resource: $rawfile('bgs/pexels-henry-acevedo-382866382-38767492.jpg'),
    isLandscape: true
  },
  {
    id: 'wood',
    nameRes: $r('app.string.home_background_preset_wood'),
    resource: $rawfile('bgs/pexels-jan-van-der-wolf-11680885-38008702.jpg'),
    isLandscape: true
  }
];

export function getAvailablePresets(isLandscape: boolean, isSmallScreen: boolean): HomeBackgroundPreset[] {
  if (isLandscape) {
    return LANDSCAPE_PRESETS;
  }
  if (isSmallScreen) {
    return PORTRAIT_PRESETS;
  }
  return PORTRAIT_PRESETS.filter((preset: HomeBackgroundPreset): boolean => !preset.smallScreenOnly);
}

export function resolvePresetResource(isLandscape: boolean, presetId?: string): Resource {
  if (isLandscape) {
    if (presetId !== undefined && presetId.length > 0) {
      const match: HomeBackgroundPreset | undefined =
        LANDSCAPE_PRESETS.find((item: HomeBackgroundPreset): boolean => item.id === presetId);
      if (match !== undefined) {
        return match.resource;
      }
    }
    return LANDSCAPE_PRESETS[0].resource;
  }

  if (presetId !== undefined && presetId.length > 0) {
    const match: HomeBackgroundPreset | undefined =
      PORTRAIT_PRESETS.find((item: HomeBackgroundPreset): boolean => item.id === presetId);
    if (match !== undefined) {
      return match.resource;
    }
  }
  return PORTRAIT_PRESETS[0].resource;
}
