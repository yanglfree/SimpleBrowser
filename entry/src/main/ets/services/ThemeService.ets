import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppearanceMode } from '../models/BrowserModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'ThemeService';

const LIGHT_BACKGROUND: string = '#FAF9F7';
const DARK_BACKGROUND: string = '#131311';
const LIGHT_CONTENT: string = '#1A1A18';
const DARK_CONTENT: string = '#F5F3EE';
const TRANSPARENT_BACKGROUND: string = '#00000000';
const HOME_CONTENT: string = '#FFFFFFFF';

/**
 * 设置 › 通用 › 外观. Switching the application colour mode is what flips every
 * `$r('app.color.*')` between `resources/base` and `resources/dark`; the system
 * bars are re-tinted to match because they are drawn outside the page.
 */
export class ThemeService {
  static apply(context: common.UIAbilityContext, appearance: AppearanceMode): void {
    try {
      context.getApplicationContext().setColorMode(ThemeService.colorModeFor(appearance));
    } catch (error) {
      Logger.warn(TAG, `Failed to set colour mode: ${String(error)}`);
    }
    ThemeService.applySystemBars(context, ThemeService.isDark(context, appearance), false);
  }

  static applySurface(
    context: common.UIAbilityContext,
    appearance: AppearanceMode,
    isHome: boolean,
    homeBackgroundEnabled: boolean
  ): void {
    ThemeService.applySystemBars(
      context,
      ThemeService.isDark(context, appearance),
      isHome && homeBackgroundEnabled
    );
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

  private static applySystemBars(context: common.UIAbilityContext, isDark: boolean, isHome: boolean): void {
    const background: string = isDark ? DARK_BACKGROUND : LIGHT_BACKGROUND;
    const content: string = isDark ? DARK_CONTENT : LIGHT_CONTENT;
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      const properties: window.SystemBarProperties = {
        statusBarColor: isHome ? TRANSPARENT_BACKGROUND : background,
        navigationBarColor: isHome ? TRANSPARENT_BACKGROUND : background,
        statusBarContentColor: isHome ? HOME_CONTENT : content,
        navigationBarContentColor: isHome ? HOME_CONTENT : content
      };
      mainWindow.setWindowBackgroundColor(background);
      mainWindow.setWindowLayoutFullScreen(isHome).then((): void => {
        mainWindow.setWindowSystemBarProperties(properties).catch((error: Error): void => {
          Logger.warn(TAG, `Failed to apply system bar style: ${String(error)}`);
        });
      }).catch((error: Error): void => {
        Logger.warn(TAG, `Failed to apply full-screen layout: ${String(error)}`);
      });
    }).catch((error: Error): void => {
      Logger.warn(TAG, `Failed to resolve main window: ${String(error)}`);
    });
  }
}
