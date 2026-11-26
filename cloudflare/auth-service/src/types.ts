export interface Env {
  AUTH_DB: D1Database;
  AVATARS?: R2Bucket;
  WALLPAPERS?: R2Bucket;
  SYNC_BUNDLES?: R2Bucket;
  APP_ID?: string;
  IAP_GATEWAY_URL?: string;
  OAUTH_REDIRECT_BASE?: string;
  RESEND_API_KEY?: string;
  RESEND_FROM?: string;
  EMAIL_WEBHOOK_URL?: string;
  ALLOW_DEV_OTP_ECHO?: string;
  APPLE_CLIENT_IDS?: string;
  APPLE_CLIENT_ID?: string;
  APPLE_CLIENT_SECRET?: string;
  GOOGLE_CLIENT_IDS?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  HUAWEI_CLIENT_ID?: string;
  HUAWEI_CLIENT_SECRET?: string;
}

export interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  salt: string;
  display_name: string;
  avatar_url?: string | null;
  created_at: number;
  updated_at: number;
}

export interface SessionRow {
  id: string;
  user_id: string;
  created_at: number;
  expires_at: number;
}

export interface SyncRow {
  user_id: string;
  bookmarks_json: string | null;
  settings_json: string | null;
  version: number;
  updated_at: number;
}

export interface UserIdentityRow {
  id: string;
  user_id: string;
  provider: string;
  provider_subject: string;
  provider_email: string | null;
  email_verified: number;
  profile_json: string | null;
  created_at: number;
  updated_at: number;
}

export const SESSION_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;

export function jsonResponse(
  data: unknown,
  headers: Record<string, string>,
  status = 200
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers,
  });
}

export function extractBearerToken(request: Request): string | null {
  const authHeader = request.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  const trimmed = authHeader.slice(7).trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function sanitizeUser(user: UserRow) {
  return {
    id: user.id,
    email: user.email,
    displayName: user.display_name,
    avatarUrl: user.avatar_url || null,
    createdAt: user.created_at,
  };
}

export function generateSalt(): string {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function generateToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function generateOtpCode(): string {
  const array = new Uint32Array(1);
  crypto.getRandomValues(array);
  return String(array[0] % 1_000_000).padStart(6, '0');
}

export async function hashPassword(password: string, salt: string): Promise<string> {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: enc.encode(salt),
      iterations: 100000,
      hash: 'SHA-256',
    },
    keyMaterial,
    256
  );

  return Array.from(new Uint8Array(derivedBits), (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function sha256Hex(input: string | ArrayBuffer | Uint8Array): Promise<string> {
  const bytes =
    typeof input === 'string'
      ? new TextEncoder().encode(input)
      : input instanceof Uint8Array
        ? input
        : new Uint8Array(input);
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  const digest = await crypto.subtle.digest('SHA-256', copy.buffer);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

export function timingSafeEqualStrings(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export function parseCsvSet(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}
