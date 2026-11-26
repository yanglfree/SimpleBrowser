import { AuthProviderKind } from '../models/AccountSyncModels';

const MAINLAND_TIMEZONES: string[] = [
  'Asia/Shanghai',
  'Asia/Chongqing',
  'Asia/Harbin',
  'Asia/Urumqi'
];

export function isMainlandChinaRegion(regionCode: string, timezone: string): boolean {
  const trimmed: string = regionCode.trim().toUpperCase();
  if (/^[A-Z]{2}$/.test(trimmed)) {
    return trimmed === 'CN';
  }
  return MAINLAND_TIMEZONES.includes(timezone.trim());
}

export function isGoogleSignInAvailable(regionCode: string, timezone: string): boolean {
  return !isMainlandChinaRegion(regionCode, timezone);
}

export function resolveHarmonyAuthProviders(regionCode: string, timezone: string): AuthProviderKind[] {
  const providers: AuthProviderKind[] = [
    AuthProviderKind.EMAIL_OTP,
    AuthProviderKind.EMAIL_PASSWORD,
    AuthProviderKind.HUAWEI
  ];
  if (isGoogleSignInAvailable(regionCode, timezone)) {
    providers.push(AuthProviderKind.GOOGLE);
  }
  return providers;
}
