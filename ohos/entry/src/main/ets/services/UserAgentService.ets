import { webview } from '@kit.ArkWeb';
import { DESKTOP_USER_AGENT } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

const TAG: string = 'UserAgentService';

/** The device default, captured the first time a controller is attached. */
let defaultUserAgent: string = '';

/**
 * Backs the 桌面版 action. ArkWeb has no "reset" for a custom user agent, so the
 * stock string is remembered on first use and restored when desktop mode is off.
 */
export class UserAgentService {
  static remember(controller: webview.WebviewController): void {
    if (defaultUserAgent.length > 0) {
      return;
    }
    try {
      defaultUserAgent = controller.getUserAgent();
    } catch (error) {
      Logger.warn(TAG, `Failed to read default user agent: ${String(error)}`);
    }
  }

  static apply(controller: webview.WebviewController, isDesktop: boolean): void {
    UserAgentService.remember(controller);
    try {
      controller.setCustomUserAgent(isDesktop ? DESKTOP_USER_AGENT : defaultUserAgent);
    } catch (error) {
      Logger.warn(TAG, `Failed to set user agent: ${String(error)}`);
    }
  }
}
