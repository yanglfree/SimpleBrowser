import { ensureAuthSyncV2Schema } from './schema.ts';
import { type Env, type UserRow, jsonResponse } from './types.ts';

interface ProBindingRow {
  id: string;
  user_id: string;
  platform: string;
  install_id: string;
  bound_at: number;
  last_verified_at: number;
  rebind_count: number;
}

interface ProEntitlementRow {
  user_id: string;
  active: number;
  scope: string;
  plan: string | null;
  product_id: string | null;
  expires_at: number;
  source_platform: string | null;
  verified_at: number;
  updated_at: number;
}

interface UpstreamEntitlement {
  active?: boolean;
  scope?: string;
  plan?: string | null;
  product_id?: string | null;
  expires_at?: number;
  verified_at?: number;
}

const MAX_PRO_BINDINGS_PER_USER = 5;
const REBIND_COOLDOWN_MS = 90 * 24 * 60 * 60 * 1000;
const REFRESH_TTL_MS = 6 * 60 * 60 * 1000;

let iapFetchOverride: typeof fetch | null = null;

export function setIapFetchOverrideForTesting(fn: typeof fetch | null): void {
  iapFetchOverride = fn;
}

function iapFetch(url: string, init?: RequestInit): Promise<Response> {
  return (iapFetchOverride ?? fetch)(url, init);
}

function formatEntitlement(row: ProEntitlementRow | null, now = Date.now()) {
  if (!row || row.active !== 1 || row.scope !== 'pro') {
    return null;
  }
  if (row.expires_at > 0 && row.expires_at <= now) {
    return null;
  }
  return {
    active: true,
    scope: row.scope,
    plan: row.plan,
    productId: row.product_id || '',
    expiresAt: row.expires_at,
    source: row.source_platform ? `cloud_${row.source_platform}` : 'cloud_sync',
    sourcePlatform: row.source_platform,
    verifiedAt: row.verified_at,
  };
}

async function queryUpstreamIapEntitlement(
  platform: string,
  installId: string,
  env: Env
): Promise<UpstreamEntitlement | null> {
  const gatewayBase = (env.IAP_GATEWAY_URL || 'https://gateway.youdroid.top').replace(/\/$/, '');
  const queryUrl =
    `${gatewayBase}/v1/iap/entitlements?platform=${encodeURIComponent(platform)}` +
    `&app_id=zhuobrowser&account_id=${encodeURIComponent(installId)}`;

  const resp = await iapFetch(queryUrl, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      'X-App-Id': 'zhuobrowser',
    },
  });
  if (!resp.ok) {
    return null;
  }
  const data = (await resp.json().catch(() => ({}))) as { entitlement?: UpstreamEntitlement | null };
  return data.entitlement || null;
}

export async function isUserProActive(userId: string, env: Env, now = Date.now()): Promise<boolean> {
  await ensureAuthSyncV2Schema(env);
  const row = await env.AUTH_DB.prepare('SELECT * FROM user_pro_entitlements WHERE user_id = ?')
    .bind(userId)
    .first<ProEntitlementRow>();
  return formatEntitlement(row, now) !== null;
}

export async function handleProBind(
  request: Request,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const body = (await request.json().catch(() => ({}))) as {
    platform?: string;
    installId?: string;
  };
  const platform = String(body.platform || '').trim().toLowerCase();
  const installId = String(body.installId || '').trim();

  if (!['harmony', 'ios', 'macos', 'android'].includes(platform) || installId.length < 4 || installId.length > 160) {
    return jsonResponse({ error: 'Invalid platform or installId' }, headers, 400);
  }

  const now = Date.now();
  const existingBinding = await env.AUTH_DB.prepare(
    'SELECT * FROM user_pro_bindings WHERE platform = ? AND install_id = ?'
  )
    .bind(platform, installId)
    .first<ProBindingRow>();

  if (existingBinding && existingBinding.user_id !== user.id) {
    if (now - existingBinding.bound_at < REBIND_COOLDOWN_MS) {
      return jsonResponse(
        { error: '该设备购买凭据已在 90 天内绑定过其他账号，请使用原账号登录', code: 'INSTALL_ALREADY_BOUND' },
        headers,
        409
      );
    }
  }

  if (!existingBinding || existingBinding.user_id !== user.id) {
    const countRow = await env.AUTH_DB.prepare(
      'SELECT COUNT(*) as total FROM user_pro_bindings WHERE user_id = ?'
    )
      .bind(user.id)
      .first<{ total: number }>();
    if ((countRow?.total || 0) >= MAX_PRO_BINDINGS_PER_USER) {
      return jsonResponse(
        { error: `每个账号最多绑定 ${MAX_PRO_BINDINGS_PER_USER} 台付费设备`, code: 'PRO_DEVICE_LIMIT_REACHED' },
        headers,
        409
      );
    }
  }

  const upstream = await queryUpstreamIapEntitlement(platform, installId, env);

  await env.AUTH_DB.prepare(
    `INSERT INTO user_pro_bindings (id, user_id, platform, install_id, bound_at, last_verified_at, rebind_count)
     VALUES (?, ?, ?, ?, ?, ?, 0)
     ON CONFLICT(platform, install_id) DO UPDATE SET
       user_id = excluded.user_id,
       bound_at = CASE WHEN user_pro_bindings.user_id = excluded.user_id THEN user_pro_bindings.bound_at ELSE excluded.bound_at END,
       last_verified_at = excluded.last_verified_at,
       rebind_count = CASE WHEN user_pro_bindings.user_id = excluded.user_id THEN user_pro_bindings.rebind_count ELSE user_pro_bindings.rebind_count + 1 END`
  )
    .bind(crypto.randomUUID(), user.id, platform, installId, now, now)
    .run();

  if (upstream && upstream.active && upstream.scope === 'pro') {
    const expiresAt = typeof upstream.expires_at === 'number' ? upstream.expires_at : 0;
    if (expiresAt <= 0 || expiresAt > now) {
      await env.AUTH_DB.prepare(
        `INSERT INTO user_pro_entitlements (user_id, active, scope, plan, product_id, expires_at, source_platform, verified_at, updated_at)
         VALUES (?, 1, 'pro', ?, ?, ?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           active = 1,
           scope = 'pro',
           plan = excluded.plan,
           product_id = excluded.product_id,
           expires_at = CASE
             WHEN excluded.expires_at = 0 OR user_pro_entitlements.expires_at = 0 THEN 0
             WHEN excluded.expires_at > user_pro_entitlements.expires_at THEN excluded.expires_at
             ELSE user_pro_entitlements.expires_at
           END,
           source_platform = excluded.source_platform,
           verified_at = excluded.verified_at,
           updated_at = excluded.updated_at`
      )
        .bind(
          user.id,
          upstream.plan || null,
          upstream.product_id || '',
          expiresAt,
          platform,
          now,
          now
        )
        .run();
    }
  }

  const current = await env.AUTH_DB.prepare('SELECT * FROM user_pro_entitlements WHERE user_id = ?')
    .bind(user.id)
    .first<ProEntitlementRow>();

  return jsonResponse(
    {
      ok: true,
      bound: true,
      entitlement: formatEntitlement(current, now),
    },
    headers
  );
}

export async function handleGetProEntitlement(
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const now = Date.now();
  let current = await env.AUTH_DB.prepare('SELECT * FROM user_pro_entitlements WHERE user_id = ?')
    .bind(user.id)
    .first<ProEntitlementRow>();

  if (!current || now - current.verified_at > REFRESH_TTL_MS) {
    const bindings = await env.AUTH_DB.prepare(
      'SELECT * FROM user_pro_bindings WHERE user_id = ? ORDER BY last_verified_at DESC'
    )
      .bind(user.id)
      .all<ProBindingRow>();

    for (const binding of bindings.results || []) {
      const upstream = await queryUpstreamIapEntitlement(binding.platform, binding.install_id, env);
      if (upstream && upstream.active && upstream.scope === 'pro') {
        const expiresAt = typeof upstream.expires_at === 'number' ? upstream.expires_at : 0;
        if (expiresAt <= 0 || expiresAt > now) {
          await env.AUTH_DB.prepare(
            `INSERT INTO user_pro_entitlements (user_id, active, scope, plan, product_id, expires_at, source_platform, verified_at, updated_at)
             VALUES (?, 1, 'pro', ?, ?, ?, ?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET
               active = 1,
               scope = 'pro',
               plan = excluded.plan,
               product_id = excluded.product_id,
               expires_at = excluded.expires_at,
               source_platform = excluded.source_platform,
               verified_at = excluded.verified_at,
               updated_at = excluded.updated_at`
          )
            .bind(
              user.id,
              upstream.plan || null,
              upstream.product_id || '',
              expiresAt,
              binding.platform,
              now,
              now
            )
            .run();
          current = await env.AUTH_DB.prepare('SELECT * FROM user_pro_entitlements WHERE user_id = ?')
            .bind(user.id)
            .first<ProEntitlementRow>();
          break;
        }
      }
    }
  }

  return jsonResponse(
    {
      ok: true,
      entitlement: formatEntitlement(current, now),
    },
    headers
  );
}
