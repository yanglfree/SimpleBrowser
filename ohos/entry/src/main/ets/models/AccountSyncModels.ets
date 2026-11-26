export enum AuthProviderKind {
  EMAIL_OTP = 'email_otp',
  EMAIL_PASSWORD = 'email_password',
  HUAWEI = 'huawei',
  GOOGLE = 'google'
}

export interface AccountUserProfile {
  id: string;
  email: string;
  displayName: string;
  avatarUrl: string;
  createdAt: number;
}

export interface LinkedIdentityItem {
  provider: string;
  email: string;
  emailVerified: boolean;
}

export interface BookmarkFolder {
  id: string;
  name: string;
  iconName: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
  isPinnedToStartPage: boolean;
}

export interface BookmarkTombstone {
  id: string;
  url: string;
  isFolder: boolean;
  deletedAt: number;
}

export interface ArticleTombstone {
  id: string;
  canonicalUrl: string;
  deletedAt: number;
}

export interface RemoteDeviceTabEntry {
  id: string;
  title: string;
  url: string;
  lastVisitedAt: number;
}

export interface RemoteDeviceTabGroup {
  deviceId: string;
  deviceName: string;
  platform: string;
  updatedAt: number;
  tabs: RemoteDeviceTabEntry[];
}
