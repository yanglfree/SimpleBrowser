/** Host-only shadows created by the former lossy session-cookie promotion. */
export const LEGACY_HUAWEI_HOST_COOKIES: string[] = [
  'state', 'urlBeforeLogin', 'authInfo', 'authdata', 'csrfToken', 'developer_userinfo',
  'x-siteId', 'x-country', 'x-userType', 'x-hd-grey', 'x-uid', 'x-teamId', 'X-HD-SESSION'
];

/** Omit Domain deliberately: the live .developer.huawei.com cookies must survive. */
export function legacyHuaweiCookieDeletion(name: string): string {
  return `${name}=; Max-Age=0; Path=/; Secure`;
}
