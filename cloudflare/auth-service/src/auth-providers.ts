import { verifyOIDCToken, type VerifiedOidcClaims } from './jwks.ts';
import { ensureAuthSyncV2Schema } from './schema.ts';
import {
  type Env,
  type UserIdentityRow,
  type UserRow,
  SESSION_LIFETIME_MS,
  generateOtpCode,
  generateSalt,
  generateToken,
  hashPassword,
  jsonResponse,
  parseCsvSet,
  sanitizeUser,
  sha256Hex,
  timingSafeEqualStrings,
} from './types.ts';

type AuthPlatform = 'ios' | 'macos' | 'harmony' | 'android' | 'web';
type NativeIdp = 'apple' | 'huawei' | 'google';

const DEFAULT_APPLE_AUDIENCES = ['com.youdroid.zhuobrowser', 'com.youdroid.zhuobrowser.mac'];
const ALLOWED_CLIENT_REDIRECT_PREFIXES = [
  'zhuobrowser-auth://oauth/callback',
  'zhuobrowser://auth/callback',
];

const APPLE_JWKS_URI = 'https://appleid.apple.com/auth/keys';
const GOOGLE_JWKS_URI = 'https://www.googleapis.com/oauth2/v3/certs';
const HUAWEI_JWKS_URI = 'https://oauth-login.cloud.huawei.com/oauth2/v3/certs';

let externalFetchOverride: typeof fetch | null = null;

export function setAuthExternalFetchForTesting(fn: typeof fetch | null): void {
  externalFetchOverride = fn;
}

function externalFetch(input: string, init?: RequestInit): Promise<Response> {
  return (externalFetchOverride ?? fetch)(input, init);
}

export function isMainlandChinaRegion(regionCode: string | null | undefined): boolean {
  return String(regionCode || '').trim().toUpperCase() === 'CN';
}

function normalizePlatform(raw: string | undefined): AuthPlatform {
  const val = String(raw || '').trim().toLowerCase();
  if (val === 'ios' || val === 'macos' || val === 'harmony' || val === 'android') {
    return val;
  }
  return 'web';
}

export async function handleGetAuthProviders(
  request: Request,
  url: URL,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  const platform = normalizePlatform(url.searchParams.get('platform') || undefined);
  const queryRegion = (url.searchParams.get('region') || '').trim().toUpperCase();
  const cfCountry = String((request as Request & { cf?: { country?: string } }).cf?.country || '')
    .trim()
    .toUpperCase();
  const effectiveRegion = /^[A-Z]{2}$/.test(queryRegion) ? queryRegion : cfCountry;
  const googleAllowed = !isMainlandChinaRegion(effectiveRegion);

  const googleClientIds = parseCsvSet(env.GOOGLE_CLIENT_IDS);
  const googleConfigured = Boolean(env.GOOGLE_CLIENT_ID || googleClientIds.length > 0);
  const appleConfigured = true; // Native Apple ID tokens validate directly against Apple JWKS
  const huaweiConfigured = Boolean(env.HUAWEI_CLIENT_ID || true);

  const providers: Array<{ id: string; enabled: boolean; configured: boolean }> = [
    {
      id: 'email_otp',
      enabled: true,
      configured: Boolean(
        env.RESEND_API_KEY || env.EMAIL || env.EMAIL_WEBHOOK_URL || env.ALLOW_DEV_OTP_ECHO === 'true'
      ),
    },
    { id: 'email_password', enabled: true, configured: true },
  ];

  if (platform === 'ios' || platform === 'macos') {
    providers.push({ id: 'apple', enabled: true, configured: appleConfigured });
  } else if (platform === 'harmony') {
    providers.push({ id: 'huawei', enabled: true, configured: huaweiConfigured });
  }

  if (googleAllowed) {
    providers.push({ id: 'google', enabled: true, configured: googleConfigured });
  }

  return jsonResponse(
    {
      ok: true,
      platform,
      region: effectiveRegion || null,
      googleAllowed,
      providers,
    },
    headers
  );
}

async function checkAndBumpRateLimit(
  env: Env,
  bucketKey: string,
  limit: number,
  windowMs: number,
  now: number
): Promise<boolean> {
  const existing = await env.AUTH_DB.prepare('SELECT count, window_start FROM auth_rate_limits WHERE bucket_key = ?')
    .bind(bucketKey)
    .first<{ count: number; window_start: number }>();

  if (!existing || now - existing.window_start >= windowMs) {
    await env.AUTH_DB.prepare(
      `INSERT INTO auth_rate_limits (bucket_key, count, window_start) VALUES (?, 1, ?)
       ON CONFLICT(bucket_key) DO UPDATE SET count = 1, window_start = excluded.window_start`
    )
      .bind(bucketKey, now)
      .run();
    return true;
  }

  if (existing.count >= limit) {
    return false;
  }

  await env.AUTH_DB.prepare('UPDATE auth_rate_limits SET count = count + 1 WHERE bucket_key = ?')
    .bind(bucketKey)
    .run();
  return true;
}

export async function handleOtpSend(
  request: Request,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const body = (await request.json().catch(() => ({}))) as { email?: string };
  const email = (body.email || '').trim().toLowerCase();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 120) {
    return jsonResponse({ error: '请输入有效的邮箱地址' }, headers, 400);
  }

  const now = Date.now();
  const clientIp = request.headers.get('CF-Connecting-IP') || 'unknown';

  // Enforce 60s cooldown, 5/hr per email, 15/hr per IP
  const latest = await env.AUTH_DB.prepare(
    'SELECT created_at FROM auth_otp_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1'
  )
    .bind(email)
    .first<{ created_at: number }>();

  if (latest && now - latest.created_at < 60 * 1000) {
    return jsonResponse({ error: '发送过于频繁，请 60 秒后再试', code: 'OTP_COOLDOWN' }, headers, 429);
  }

  const emailAllowed = await checkAndBumpRateLimit(env, `otp:email:${email}`, 5, 60 * 60 * 1000, now);
  if (!emailAllowed) {
    return jsonResponse({ error: '该邮箱验证码请求次数已达上限，请 1 小时后再试' }, headers, 429);
  }

  const ipAllowed = await checkAndBumpRateLimit(env, `otp:ip:${clientIp}`, 15, 60 * 60 * 1000, now);
  if (!ipAllowed) {
    return jsonResponse({ error: '当前网络请求过于频繁，请稍后再试' }, headers, 429);
  }

  const code = generateOtpCode();
  const salt = generateSalt();
  const codeHash = await sha256Hex(`${salt}:${code}`);
  const expiresAt = now + 10 * 60 * 1000;
  const otpId = crypto.randomUUID();

  await env.AUTH_DB.prepare(
    `INSERT INTO auth_otp_codes (id, email, code_hash, salt, attempts, expires_at, created_at, request_ip)
     VALUES (?, ?, ?, ?, 0, ?, ?, ?)`
  )
    .bind(otpId, email, codeHash, salt, expiresAt, now, clientIp)
    .run();

  let delivered = false;
  if (env.RESEND_API_KEY) {
    const resp = await externalFetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: env.RESEND_FROM || 'ZhuoBrowser <noreply@youdroid.top>',
        to: [email],
        subject: '卓阅浏览器登录验证码',
        text: `你的卓阅浏览器登录验证码为：${code}（10 分钟内有效，请勿泄露给他人）。`,
      }),
    });
    delivered = resp.ok;
  } else if (env.EMAIL) {
    try {
      const fromEmail = (env.EMAIL_FROM || 'noreply@auth-mail.youdroid.top').trim();
      const fromName = (env.EMAIL_FROM_NAME || '卓阅浏览器').trim();
      const result = await env.EMAIL.send({
        from: { email: fromEmail, name: fromName },
        to: [email],
        subject: '卓阅浏览器登录验证码',
        text: `你的卓阅浏览器登录验证码为：${code}（10 分钟内有效，请勿泄露给他人）。`,
        html: `<p>你的卓阅浏览器登录验证码为：<strong>${code}</strong></p><p>10 分钟内有效，请勿泄露给他人。</p>`,
      });
      delivered = Boolean(result?.messageId);
    } catch {
      delivered = false;
    }
  } else if (env.EMAIL_WEBHOOK_URL) {
    const resp = await externalFetch(env.EMAIL_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, code, expiresInMinutes: 10 }),
    });
    delivered = resp.ok;
  } else if (env.ALLOW_DEV_OTP_ECHO === 'true') {
    delivered = true;
  } else {
    await env.AUTH_DB.prepare('DELETE FROM auth_otp_codes WHERE id = ?').bind(otpId).run();
    return jsonResponse(
      {
        error: '邮件验证码通道尚未配置，请先使用邮箱密码或第三方账号登录',
        code: 'OTP_DELIVERY_NOT_CONFIGURED',
      },
      headers,
      503
    );
  }

  if (!delivered) {
    return jsonResponse({ error: '验证码发送失败，请稍后重试' }, headers, 502);
  }

  return jsonResponse(
    {
      ok: true,
      expiresInSeconds: 600,
      ...(env.ALLOW_DEV_OTP_ECHO === 'true' ? { devCode: code } : {}),
    },
    headers
  );
}

export async function handleOtpVerify(
  request: Request,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const body = (await request.json().catch(() => ({}))) as {
    email?: string;
    code?: string;
    displayName?: string;
    deviceId?: string;
    deviceName?: string;
    platform?: string;
  };

  const email = (body.email || '').trim().toLowerCase();
  const code = (body.code || '').trim();
  if (!email || !/^\d{6}$/.test(code)) {
    return jsonResponse({ error: '请输入有效的邮箱和 6 位数字验证码' }, headers, 400);
  }

  const now = Date.now();
  const row = await env.AUTH_DB.prepare(
    'SELECT * FROM auth_otp_codes WHERE email = ? AND expires_at > ? ORDER BY created_at DESC LIMIT 1'
  )
    .bind(email, now)
    .first<{
      id: string;
      email: string;
      code_hash: string;
      salt: string;
      attempts: number;
      expires_at: number;
    }>();

  if (!row) {
    return jsonResponse({ error: '验证码已过期或不存在，请重新获取' }, headers, 401);
  }

  if (row.attempts >= 5) {
    return jsonResponse({ error: '验证码错误次数过多，请重新获取' }, headers, 429);
  }

  const expectedHash = await sha256Hex(`${row.salt}:${code}`);
  if (!timingSafeEqualStrings(expectedHash, row.code_hash)) {
    await env.AUTH_DB.prepare('UPDATE auth_otp_codes SET attempts = attempts + 1 WHERE id = ?')
      .bind(row.id)
      .run();
    return jsonResponse({ error: '验证码不正确' }, headers, 401);
  }

  // Consume OTP
  await env.AUTH_DB.prepare('DELETE FROM auth_otp_codes WHERE email = ?').bind(email).run();

  let isNewUser = false;
  let user = await env.AUTH_DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first<UserRow>();
  if (!user) {
    isNewUser = true;
    const userId = crypto.randomUUID();
    const displayName = (body.displayName || '').trim() || email.split('@')[0] || '用户';
    const salt = generateSalt();
    const unusableSecret = generateToken();
    const passwordHash = await hashPassword(unusableSecret, salt);
    await env.AUTH_DB.prepare(
      'INSERT INTO users (id, email, password_hash, salt, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    )
      .bind(userId, email, passwordHash, salt, displayName, now, now)
      .run();
    user = {
      id: userId,
      email,
      password_hash: passwordHash,
      salt,
      display_name: displayName,
      avatar_url: null,
      created_at: now,
      updated_at: now,
    };
  }

  await upsertUserIdentity(env, {
    userId: user.id,
    provider: 'email',
    subject: email,
    email,
    emailVerified: true,
    profileJson: JSON.stringify({ email }),
    now,
  });

  const token = await createSessionWithDevice(env, user.id, {
    deviceId: body.deviceId,
    deviceName: body.deviceName,
    platform: body.platform,
    now,
  });
  const identities = await listUserIdentities(env, user.id);

  return jsonResponse(
    {
      ok: true,
      token,
      isNewUser,
      user: sanitizeUser(user),
      identities,
    },
    headers
  );
}

export async function handleNativeOAuth(
  request: Request,
  env: Env,
  authenticatedUser: UserRow | null,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const body = (await request.json().catch(() => ({}))) as {
    provider?: string;
    idToken?: string;
    authorizationCode?: string;
    displayName?: string;
    nonce?: string;
    deviceId?: string;
    deviceName?: string;
    platform?: string;
  };

  const provider = String(body.provider || '').trim().toLowerCase() as NativeIdp;
  if (provider !== 'apple' && provider !== 'huawei' && provider !== 'google') {
    return jsonResponse({ error: 'Unsupported OAuth provider' }, headers, 400);
  }

  let claims: VerifiedOidcClaims;
  try {
    claims = await verifyProviderCredentials(provider, body.idToken, body.authorizationCode, body.nonce, env);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: `第三方身份校验失败: ${msg}` }, headers, 401);
  }

  const now = Date.now();
  const { user, isNewUser } = await resolveOrLinkIdentityUser(env, {
    provider,
    claims,
    fallbackDisplayName: body.displayName,
    linkToUser: authenticatedUser,
    now,
  });

  const token = await createSessionWithDevice(env, user.id, {
    deviceId: body.deviceId,
    deviceName: body.deviceName,
    platform: body.platform,
    now,
  });
  const identities = await listUserIdentities(env, user.id);

  return jsonResponse(
    {
      ok: true,
      token,
      isNewUser,
      user: sanitizeUser(user),
      identities,
    },
    headers
  );
}

export async function handleOAuthStart(
  providerRaw: string,
  url: URL,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const provider = providerRaw.toLowerCase();
  if (provider !== 'google' && provider !== 'apple') {
    return jsonResponse({ error: 'Unsupported browser OAuth provider' }, headers, 400);
  }

  const clientRedirectUri = (url.searchParams.get('client_redirect_uri') || '').trim();
  const isAllowedRedirect = ALLOWED_CLIENT_REDIRECT_PREFIXES.some((prefix) =>
    clientRedirectUri.startsWith(prefix)
  );
  if (!isAllowedRedirect) {
    return jsonResponse({ error: 'Invalid client_redirect_uri' }, headers, 400);
  }

  const platform = normalizePlatform(url.searchParams.get('platform') || undefined);
  const state = generateToken();
  const codeVerifier = generateToken();
  const now = Date.now();
  const expiresAt = now + 10 * 60 * 1000;

  await env.AUTH_DB.prepare(
    `INSERT INTO oauth_states (state, provider, platform, client_redirect_uri, code_verifier, link_user_id, expires_at, created_at)
     VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`
  )
    .bind(state, provider, platform, clientRedirectUri, codeVerifier, expiresAt, now)
    .run();

  const redirectBase = (env.OAUTH_REDIRECT_BASE || url.origin).replace(/\/$/, '');
  const callbackUri = `${redirectBase}/api/auth/oauth/${provider}/callback`;

  if (provider === 'google') {
    const clientId = env.GOOGLE_CLIENT_ID || parseCsvSet(env.GOOGLE_CLIENT_IDS)[0] || '';
    if (!clientId) {
      return jsonResponse({ error: 'Google OAuth Client ID 未配置', code: 'GOOGLE_NOT_CONFIGURED' }, headers, 503);
    }
    const challengeBytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(codeVerifier));
    const codeChallenge = base64UrlEncode(new Uint8Array(challengeBytes));
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', clientId);
    authUrl.searchParams.set('redirect_uri', callbackUri);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('scope', 'openid email profile');
    authUrl.searchParams.set('state', state);
    authUrl.searchParams.set('code_challenge', codeChallenge);
    authUrl.searchParams.set('code_challenge_method', 'S256');
    authUrl.searchParams.set('prompt', 'select_account');
    return Response.redirect(authUrl.toString(), 302);
  }

  const appleClientId = env.APPLE_CLIENT_ID || parseCsvSet(env.APPLE_CLIENT_IDS)[0] || '';
  if (!appleClientId) {
    return jsonResponse({ error: 'Apple OAuth Service ID 未配置', code: 'APPLE_NOT_CONFIGURED' }, headers, 503);
  }
  const appleAuthUrl = new URL('https://appleid.apple.com/auth/authorize');
  appleAuthUrl.searchParams.set('client_id', appleClientId);
  appleAuthUrl.searchParams.set('redirect_uri', callbackUri);
  appleAuthUrl.searchParams.set('response_type', 'code');
  appleAuthUrl.searchParams.set('response_mode', 'form_post');
  appleAuthUrl.searchParams.set('scope', 'name email');
  appleAuthUrl.searchParams.set('state', state);
  return Response.redirect(appleAuthUrl.toString(), 302);
}

export async function handleOAuthCallback(
  providerRaw: string,
  request: Request,
  url: URL,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const provider = providerRaw.toLowerCase();
  if (provider !== 'google' && provider !== 'apple') {
    return jsonResponse({ error: 'Unsupported OAuth provider' }, headers, 400);
  }

  let code = url.searchParams.get('code') || '';
  let state = url.searchParams.get('state') || '';
  let errorParam = url.searchParams.get('error') || '';
  let userDisplayName = '';

  if (request.method === 'POST') {
    const formText = await request.text();
    const form = new URLSearchParams(formText);
    code = form.get('code') || code;
    state = form.get('state') || state;
    errorParam = form.get('error') || errorParam;
    const rawUser = form.get('user');
    if (rawUser) {
      try {
        const parsed = JSON.parse(rawUser) as { name?: { firstName?: string; lastName?: string } };
        const fullName = `${parsed.name?.firstName || ''} ${parsed.name?.lastName || ''}`.trim();
        if (fullName) userDisplayName = fullName;
      } catch {
        // Ignore optional name payload
      }
    }
  }

  const now = Date.now();
  const stateRow = await env.AUTH_DB.prepare(
    'SELECT * FROM oauth_states WHERE state = ? AND provider = ? AND expires_at > ?'
  )
    .bind(state, provider, now)
    .first<{
      state: string;
      provider: string;
      platform: string;
      client_redirect_uri: string;
      code_verifier: string;
      link_user_id: string | null;
    }>();

  if (!stateRow) {
    return jsonResponse({ error: 'OAuth state invalid or expired' }, headers, 400);
  }

  await env.AUTH_DB.prepare('DELETE FROM oauth_states WHERE state = ?').bind(state).run();

  if (errorParam || !code) {
    const failUrl = new URL(stateRow.client_redirect_uri);
    failUrl.searchParams.set('error', errorParam || 'missing_code');
    return Response.redirect(failUrl.toString(), 302);
  }

  const redirectBase = (env.OAUTH_REDIRECT_BASE || url.origin).replace(/\/$/, '');
  const callbackUri = `${redirectBase}/api/auth/oauth/${provider}/callback`;

  let idToken = '';
  if (provider === 'google') {
    const clientId = env.GOOGLE_CLIENT_ID || parseCsvSet(env.GOOGLE_CLIENT_IDS)[0] || '';
    const tokenResp = await externalFetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        ...(env.GOOGLE_CLIENT_SECRET ? { client_secret: env.GOOGLE_CLIENT_SECRET } : {}),
        redirect_uri: callbackUri,
        grant_type: 'authorization_code',
        code_verifier: stateRow.code_verifier,
      }).toString(),
    });
    const tokenJson = (await tokenResp.json().catch(() => ({}))) as { id_token?: string };
    if (!tokenResp.ok || !tokenJson.id_token) {
      const failUrl = new URL(stateRow.client_redirect_uri);
      failUrl.searchParams.set('error', 'token_exchange_failed');
      return Response.redirect(failUrl.toString(), 302);
    }
    idToken = tokenJson.id_token;
  } else {
    const clientId = env.APPLE_CLIENT_ID || parseCsvSet(env.APPLE_CLIENT_IDS)[0] || '';
    const tokenResp = await externalFetch('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: env.APPLE_CLIENT_SECRET || '',
        redirect_uri: callbackUri,
        grant_type: 'authorization_code',
      }).toString(),
    });
    const tokenJson = (await tokenResp.json().catch(() => ({}))) as { id_token?: string };
    if (!tokenResp.ok || !tokenJson.id_token) {
      const failUrl = new URL(stateRow.client_redirect_uri);
      failUrl.searchParams.set('error', 'apple_token_exchange_failed');
      return Response.redirect(failUrl.toString(), 302);
    }
    idToken = tokenJson.id_token;
  }

  let claims: VerifiedOidcClaims;
  try {
    claims = await verifyProviderCredentials(provider as NativeIdp, idToken, undefined, undefined, env);
  } catch {
    const failUrl = new URL(stateRow.client_redirect_uri);
    failUrl.searchParams.set('error', 'id_token_invalid');
    return Response.redirect(failUrl.toString(), 302);
  }

  const { user, isNewUser } = await resolveOrLinkIdentityUser(env, {
    provider,
    claims,
    fallbackDisplayName: userDisplayName,
    linkToUser: null,
    now,
  });

  const sessionToken = await createSessionWithDevice(env, user.id, {
    platform: stateRow.platform,
    now,
  });

  const ticket = generateToken();
  await env.AUTH_DB.prepare(
    `INSERT INTO oauth_tickets (ticket, user_id, session_token, is_new_user, expires_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  )
    .bind(ticket, user.id, sessionToken, isNewUser ? 1 : 0, now + 2 * 60 * 1000, now)
    .run();

  const successUrl = new URL(stateRow.client_redirect_uri);
  successUrl.searchParams.set('ticket', ticket);
  return Response.redirect(successUrl.toString(), 302);
}

export async function handleOAuthExchange(
  request: Request,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const body = (await request.json().catch(() => ({}))) as { ticket?: string };
  const ticket = (body.ticket || '').trim();
  if (!ticket) {
    return jsonResponse({ error: 'Ticket is required' }, headers, 400);
  }

  const now = Date.now();
  const ticketRow = await env.AUTH_DB.prepare(
    'SELECT * FROM oauth_tickets WHERE ticket = ? AND expires_at > ?'
  )
    .bind(ticket, now)
    .first<{
      ticket: string;
      user_id: string;
      session_token: string;
      is_new_user: number;
    }>();

  if (!ticketRow) {
    return jsonResponse({ error: 'OAuth ticket expired or invalid' }, headers, 401);
  }

  await env.AUTH_DB.prepare('DELETE FROM oauth_tickets WHERE ticket = ?').bind(ticket).run();

  const user = await env.AUTH_DB.prepare('SELECT * FROM users WHERE id = ?')
    .bind(ticketRow.user_id)
    .first<UserRow>();

  if (!user) {
    return jsonResponse({ error: 'User not found' }, headers, 404);
  }

  const identities = await listUserIdentities(env, user.id);
  return jsonResponse(
    {
      ok: true,
      token: ticketRow.session_token,
      isNewUser: ticketRow.is_new_user === 1,
      user: sanitizeUser(user),
      identities,
    },
    headers
  );
}

export async function handleListIdentities(
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const identities = await listUserIdentities(env, user.id);
  return jsonResponse({ ok: true, identities }, headers);
}

export async function handleUnlinkIdentity(
  providerRaw: string,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const provider = providerRaw.trim().toLowerCase();
  const identities = await listUserIdentities(env, user.id);
  const target = identities.find((item) => item.provider === provider);
  if (!target) {
    return jsonResponse({ error: 'Identity not linked' }, headers, 404);
  }

  if (identities.length <= 1) {
    return jsonResponse(
      { error: '至少需要保留一种登录方式，无法解绑唯一登录凭据' },
      headers,
      400
    );
  }

  await env.AUTH_DB.prepare('DELETE FROM user_identities WHERE user_id = ? AND provider = ?')
    .bind(user.id, provider)
    .run();

  const updated = await listUserIdentities(env, user.id);
  return jsonResponse({ ok: true, identities: updated }, headers);
}

export async function handleListDevices(
  user: UserRow,
  currentToken: string | null,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const currentSessionId = currentToken ? await sha256Hex(currentToken) : '';
  const rows = await env.AUTH_DB.prepare(
    'SELECT session_id, device_id, device_name, platform, created_at, last_seen_at, expires_at FROM device_sessions WHERE user_id = ? AND expires_at > ? ORDER BY last_seen_at DESC'
  )
    .bind(user.id, Date.now())
    .all<{
      session_id: string;
      device_id: string;
      device_name: string;
      platform: string;
      created_at: number;
      last_seen_at: number;
      expires_at: number;
    }>();

  const devices = (rows.results || []).map((row) => ({
    deviceId: row.device_id,
    deviceName: row.device_name,
    platform: row.platform,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    isCurrent: row.session_id === currentSessionId,
  }));

  return jsonResponse({ ok: true, devices }, headers);
}

export async function verifyProviderCredentials(
  provider: NativeIdp,
  idToken: string | undefined,
  authorizationCode: string | undefined,
  nonce: string | undefined,
  env: Env
): Promise<VerifiedOidcClaims> {
  if (provider === 'apple') {
    if (!idToken) throw new Error('Apple identityToken is required');
    const configured = parseCsvSet(env.APPLE_CLIENT_IDS);
    const audiences = configured.length > 0 ? configured : DEFAULT_APPLE_AUDIENCES;
    return await verifyOIDCToken({
      idToken,
      jwksUri: APPLE_JWKS_URI,
      expectedIssuers: ['https://appleid.apple.com'],
      expectedAudiences: audiences,
      expectedNonce: nonce,
    });
  }

  if (provider === 'google') {
    if (!idToken) throw new Error('Google idToken is required');
    const configured = parseCsvSet(env.GOOGLE_CLIENT_IDS);
    if (env.GOOGLE_CLIENT_ID && !configured.includes(env.GOOGLE_CLIENT_ID)) {
      configured.push(env.GOOGLE_CLIENT_ID);
    }
    return await verifyOIDCToken({
      idToken,
      jwksUri: GOOGLE_JWKS_URI,
      expectedIssuers: ['https://accounts.google.com', 'accounts.google.com'],
      expectedAudiences: configured,
      expectedNonce: nonce,
    });
  }

  // Huawei Account Kit
  if (idToken) {
    const audiences = env.HUAWEI_CLIENT_ID ? [env.HUAWEI_CLIENT_ID] : [];
    return await verifyOIDCToken({
      idToken,
      jwksUri: HUAWEI_JWKS_URI,
      expectedIssuers: ['https://accounts.huawei.com', 'https://oauth-login.cloud.huawei.com'],
      expectedAudiences: audiences,
      expectedNonce: nonce,
    });
  }

  if (authorizationCode && env.HUAWEI_CLIENT_ID && env.HUAWEI_CLIENT_SECRET) {
    const tokenResp = await externalFetch('https://oauth-login.cloud.huawei.com/oauth2/v3/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: env.HUAWEI_CLIENT_ID,
        client_secret: env.HUAWEI_CLIENT_SECRET,
        code: authorizationCode,
      }).toString(),
    });
    const tokenJson = (await tokenResp.json().catch(() => ({}))) as { id_token?: string };
    if (!tokenResp.ok || !tokenJson.id_token) {
      throw new Error('Huawei authorizationCode exchange failed');
    }
    return await verifyOIDCToken({
      idToken: tokenJson.id_token,
      jwksUri: HUAWEI_JWKS_URI,
      expectedIssuers: ['https://accounts.huawei.com', 'https://oauth-login.cloud.huawei.com'],
      expectedAudiences: [env.HUAWEI_CLIENT_ID],
    });
  }

  throw new Error('Huawei idToken or authorizationCode is required');
}

async function resolveOrLinkIdentityUser(
  env: Env,
  params: {
    provider: string;
    claims: VerifiedOidcClaims;
    fallbackDisplayName?: string;
    linkToUser: UserRow | null;
    now: number;
  }
): Promise<{ user: UserRow; isNewUser: boolean }> {
  const { provider, claims, fallbackDisplayName, linkToUser, now } = params;
  const emailVerified = claims.email_verified === true || claims.email_verified === 'true';
  const normalizedEmail = claims.email ? claims.email.trim().toLowerCase() : null;

  const existingIdentity = await env.AUTH_DB.prepare(
    'SELECT * FROM user_identities WHERE provider = ? AND provider_subject = ?'
  )
    .bind(provider, claims.sub)
    .first<UserIdentityRow>();

  if (linkToUser) {
    if (existingIdentity && existingIdentity.user_id !== linkToUser.id) {
      throw new Error('该第三方账号已绑定至其他卓阅账号');
    }
    await upsertUserIdentity(env, {
      userId: linkToUser.id,
      provider,
      subject: claims.sub,
      email: normalizedEmail,
      emailVerified,
      profileJson: JSON.stringify({ name: claims.name || fallbackDisplayName || null }),
      now,
    });
    return { user: linkToUser, isNewUser: false };
  }

  if (existingIdentity) {
    const matchedUser = await env.AUTH_DB.prepare('SELECT * FROM users WHERE id = ?')
      .bind(existingIdentity.user_id)
      .first<UserRow>();
    if (matchedUser) {
      await upsertUserIdentity(env, {
        userId: matchedUser.id,
        provider,
        subject: claims.sub,
        email: normalizedEmail,
        emailVerified,
        profileJson: JSON.stringify({ name: claims.name || fallbackDisplayName || null }),
        now,
      });
      return { user: matchedUser, isNewUser: false };
    }
  }

  if (normalizedEmail && emailVerified) {
    const emailOwner = await env.AUTH_DB.prepare('SELECT * FROM users WHERE email = ?')
      .bind(normalizedEmail)
      .first<UserRow>();
    if (emailOwner) {
      await upsertUserIdentity(env, {
        userId: emailOwner.id,
        provider,
        subject: claims.sub,
        email: normalizedEmail,
        emailVerified: true,
        profileJson: JSON.stringify({ name: claims.name || fallbackDisplayName || null }),
        now,
      });
      return { user: emailOwner, isNewUser: false };
    }
  }

  // Create new user with synthetic private email fallback if IdP hides email (e.g. Apple private relay omitted)
  const userId = crypto.randomUUID();
  const assignedEmail = normalizedEmail || `${provider}_${claims.sub.slice(0, 24)}@id.zhuobrowser.local`;
  const displayName =
    (fallbackDisplayName || claims.name || '').trim() ||
    (normalizedEmail ? normalizedEmail.split('@')[0] : '卓阅用户');
  const salt = generateSalt();
  const passwordHash = await hashPassword(generateToken(), salt);

  await env.AUTH_DB.prepare(
    'INSERT INTO users (id, email, password_hash, salt, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  )
    .bind(userId, assignedEmail, passwordHash, salt, displayName, now, now)
    .run();

  const newUser: UserRow = {
    id: userId,
    email: assignedEmail,
    password_hash: passwordHash,
    salt,
    display_name: displayName,
    avatar_url: null,
    created_at: now,
    updated_at: now,
  };

  await upsertUserIdentity(env, {
    userId,
    provider,
    subject: claims.sub,
    email: normalizedEmail,
    emailVerified,
    profileJson: JSON.stringify({ name: displayName }),
    now,
  });

  return { user: newUser, isNewUser: true };
}

export async function upsertUserIdentity(
  env: Env,
  input: {
    userId: string;
    provider: string;
    subject: string;
    email: string | null;
    emailVerified: boolean;
    profileJson: string;
    now: number;
  }
): Promise<void> {
  await env.AUTH_DB.prepare(
    `INSERT INTO user_identities (id, user_id, provider, provider_subject, provider_email, email_verified, profile_json, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(provider, provider_subject) DO UPDATE SET
       user_id = excluded.user_id,
       provider_email = COALESCE(excluded.provider_email, user_identities.provider_email),
       email_verified = MAX(excluded.email_verified, user_identities.email_verified),
       profile_json = excluded.profile_json,
       updated_at = excluded.updated_at`
  )
    .bind(
      crypto.randomUUID(),
      input.userId,
      input.provider,
      input.subject,
      input.email,
      input.emailVerified ? 1 : 0,
      input.profileJson,
      input.now,
      input.now
    )
    .run();
}

export async function listUserIdentities(env: Env, userId: string) {
  const rows = await env.AUTH_DB.prepare(
    'SELECT provider, provider_email, email_verified, created_at, updated_at FROM user_identities WHERE user_id = ? ORDER BY created_at ASC'
  )
    .bind(userId)
    .all<{
      provider: string;
      provider_email: string | null;
      email_verified: number;
      created_at: number;
      updated_at: number;
    }>();

  return (rows.results || []).map((row) => ({
    provider: row.provider,
    email: row.provider_email,
    emailVerified: row.email_verified === 1,
    linkedAt: row.created_at,
  }));
}

export async function createSessionWithDevice(
  env: Env,
  userId: string,
  meta: {
    deviceId?: string;
    deviceName?: string;
    platform?: string;
    now: number;
  }
): Promise<string> {
  const token = generateToken();
  const expiresAt = meta.now + SESSION_LIFETIME_MS;
  await env.AUTH_DB.prepare('INSERT INTO sessions (id, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)')
    .bind(token, userId, meta.now, expiresAt)
    .run();

  const deviceId = (meta.deviceId || '').trim() || `dev-${crypto.randomUUID().slice(0, 8)}`;
  const deviceName = (meta.deviceName || '').trim() || '卓阅设备';
  const platform = normalizePlatform(meta.platform);
  const sessionKey = await sha256Hex(token);

  await env.AUTH_DB.prepare(
    `INSERT INTO device_sessions (session_id, user_id, device_id, device_name, platform, created_at, last_seen_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(sessionKey, userId, deviceId, deviceName, platform, meta.now, meta.now, expiresAt)
    .run();

  return token;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
