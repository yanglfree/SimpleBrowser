import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppearanceMode } from '../models/BrowserModels';
import { BrowserSystemBarStyle } from '../models/SystemBarStyle';
import { Logger } from '../utils/Logger';

const TAG: string = 'ThemeService';

const TRANSPARENT_BACKGROUND: string = '#00000000';

/** Keeps the ArkUI origin stable while surface colours change between tabs. */
export function shouldLayoutFullScreen(_isHome: boolean): boolean {
  return true;
}

export function systemBarBackgroundColor(isFullScreen: boolean, background: string): string {
  return isFullScreen ? TRANSPARENT_BACKGROUND : background;
}

/**
 * 设置 › 通用 › 外观. Switching the application colour mode is what flips every
 * `$r('app.color.*')` between `resources/base` and `resources/dark`.
 * The root page owns the matching backdrop and native system bar style.
 */
export class ThemeService {
  static apply(context: common.UIAbilityContext, appearance: AppearanceMode): void {
    try {
      context.getApplicationContext().setColorMode(ThemeService.colorModeFor(appearance));
    } catch (error) {
      Logger.warn(TAG, `Failed to set colour mode: ${String(error)}`);
    }
  }

  private static revisions: WeakMap<common.UIAbilityContext, number> = new WeakMap();

  static async applySurface(context: common.UIAbilityContext, style: BrowserSystemBarStyle): Promise<void> {
    const revision: number = (ThemeService.revisions.get(context) ?? 0) + 1;
    ThemeService.revisions.set(context, revision);
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      if (ThemeService.revisions.get(context) !== revision) {
        return;
      }
      const isFullScreen: boolean = shouldLayoutFullScreen(style.wallpaper);
      if (mainWindow.getWindowProperties().isLayoutFullScreen !== isFullScreen) {
        await mainWindow.setWindowLayoutFullScreen(isFullScreen);
      }
      if (ThemeService.revisions.get(context) !== revision) {
        return;
      }
      mainWindow.setWindowBackgroundColor(style.background);
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: systemBarBackgroundColor(isFullScreen, style.background),
        navigationBarColor: systemBarBackgroundColor(isFullScreen, style.background),
        statusBarContentColor: style.content,
        navigationBarContentColor: style.content
      });
    } catch (error) {
      Logger.warn(TAG, `Failed to apply system bar style: ${String(error)}`);
      throw new Error(String(error));
    }
  }

  static isDark(context: common.UIAbilityContext, appearance: AppearanceMode): boolean {
    if (appearance === AppearanceMode.Dark) {
      return true;
    }
    if (appearance === AppearanceMode.Light) {
      return false;
    }
    return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private static colorModeFor(appearance: AppearanceMode): ConfigurationConstant.ColorMode {
    if (appearance === AppearanceMode.Dark) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (appearance === AppearanceMode.Light) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
}
