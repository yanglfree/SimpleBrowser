import { common, Want } from '@kit.AbilityKit';

export enum ExternalProtocolCategory {
  AppInstall = 'app_install',
  Communication = 'communication',
  Navigation = 'navigation',
  Payment = 'payment',
  Social = 'social',
  FileTransfer = 'file_transfer',
  Custom = 'custom'
}

export interface ExternalProtocolRequest {
  url: string;
  scheme: string;
  category: ExternalProtocolCategory;
  sourceHost: string;
}

const WEB_SCHEMES: string[] = [
  'http', 'https', 'about', 'data', 'blob', 'file', 'resource', 'browser'
];

// These schemes execute inside a web runtime or target privileged debugging
// surfaces. They must never be handed to another application.
const BLOCKED_SCHEMES: string[] = [
  'javascript', 'arkweb', 'chrome', 'chrome-devtools', 'devtools'
];

const APP_INSTALL_SCHEMES: string[] = [
  'store', 'market', 'appmarket', 'intent', 'hap'
];
const COMMUNICATION_SCHEMES: string[] = [
  'tel', 'sms', 'smsto', 'mms', 'mmsto', 'mailto', 'sip', 'im'
];
const NAVIGATION_SCHEMES: string[] = [
  'geo', 'map', 'maps', 'amap', 'baidumap', 'petalmaps'
];
const PAYMENT_SCHEMES: string[] = [
  'alipay', 'alipays', 'weixin', 'wechat', 'wxp', 'unionpay', 'upwallet'
];
const SOCIAL_SCHEMES: string[] = [
  'mqq', 'mqqapi', 'qq', 'sinaweibo', 'weibo', 'zhihu', 'bilibili',
  'taobao', 'openapp.jdmobile'
];
const FILE_TRANSFER_SCHEMES: string[] = [
  'ftp', 'ftps', 'sftp', 'magnet', 'ed2k'
];

function includesScheme(schemes: string[], scheme: string): boolean {
  return schemes.includes(scheme);
}

export function protocolScheme(url: string): string {
  const match: RegExpMatchArray | null = url.trim().match(/^([a-z][a-z0-9+.-]*):/i);
  return match === null ? '' : match[1].toLowerCase();
}

export function isWebProtocol(url: string): boolean {
  return includesScheme(WEB_SCHEMES, protocolScheme(url));
}

export function isBlockedProtocol(url: string): boolean {
  return includesScheme(BLOCKED_SCHEMES, protocolScheme(url));
}

export function externalProtocolCategory(scheme: string): ExternalProtocolCategory {
  if (includesScheme(APP_INSTALL_SCHEMES, scheme)) {
    return ExternalProtocolCategory.AppInstall;
  }
  if (includesScheme(COMMUNICATION_SCHEMES, scheme)) {
    return ExternalProtocolCategory.Communication;
  }
  if (includesScheme(NAVIGATION_SCHEMES, scheme)) {
    return ExternalProtocolCategory.Navigation;
  }
  if (includesScheme(PAYMENT_SCHEMES, scheme)) {
    return ExternalProtocolCategory.Payment;
  }
  if (includesScheme(SOCIAL_SCHEMES, scheme)) {
    return ExternalProtocolCategory.Social;
  }
  if (includesScheme(FILE_TRANSFER_SCHEMES, scheme)) {
    return ExternalProtocolCategory.FileTransfer;
  }
  return ExternalProtocolCategory.Custom;
}

export function createExternalProtocolRequest(
  url: string,
  sourceHost: string = ''
): ExternalProtocolRequest | undefined {
  const value: string = url.trim();
  const scheme: string = protocolScheme(value);
  if (scheme.length === 0 || includesScheme(WEB_SCHEMES, scheme) || includesScheme(BLOCKED_SCHEMES, scheme)) {
    return undefined;
  }
  return {
    url: value,
    scheme: scheme,
    category: externalProtocolCategory(scheme),
    sourceHost: sourceHost
  };
}

export class ExternalProtocolService {
  static async open(
    context: common.UIAbilityContext,
    request: ExternalProtocolRequest
  ): Promise<boolean> {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: request.url
    };
    try {
      await context.startAbility(want);
      return true;
    } catch (_error) {
      return false;
    }
  }
}
