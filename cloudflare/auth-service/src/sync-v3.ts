import { isUserProActive } from './pro-entitlement.ts';
import { ensureAuthSyncV2Schema } from './schema.ts';
import { type Env, type SyncRow, type UserRow, jsonResponse, sha256Hex } from './types.ts';

const VALID_SCOPES = new Set(['bookmarks', 'settings', 'site_controls', 'articles_meta']);
const MAX_ARTICLE_BUNDLE_BYTES = 5 * 1024 * 1024;
const MAX_DEVICE_TABS = 50;

interface SyncScopeRow {
  user_id: string;
  scope: string;
  payload_json: string;
  encryption_mode: string;
  version: number;
  updated_at: number;
  updated_by_device_id: string | null;
}

interface DeviceTabRow {
  user_id: string;
  device_id: string;
  device_name: string;
  platform: string;
  tabs_json: string;
  encryption_mode: string;
  updated_at: number;
}

interface PushScopeInput {
  baseVersion?: number;
  encryptionMode?: string;
  payload?: unknown;
}

interface IncomingTab {
  id?: string;
  title?: string;
  url?: string;
  isPrivate?: boolean;
  lastVisitedAt?: number;
}

function isInternalOrBlankUrl(url: string): boolean {
  const trimmed = url.trim().toLowerCase();
  if (!trimmed || trimmed === 'about:blank') return true;
  return (
    trimmed.startsWith('browser://') ||
    trimmed.startsWith('zhuo://') ||
    trimmed.startsWith('javascript:') ||
    trimmed.startsWith('data:')
  );
}

function sanitizeTabs(tabs: IncomingTab[]): Array<{ id: string; title: string; url: string; lastVisitedAt: number }> {
  const clean: Array<{ id: string; title: string; url: string; lastVisitedAt: number }> = [];
  const seen = new Set<string>();
  for (const tab of tabs) {
    if (!tab || tab.isPrivate) continue;
    const url = String(tab.url || '').trim();
    if (isInternalOrBlankUrl(url)) continue;
    const norm = url.replace(/\/+$/, '').toLowerCase();
    if (seen.has(norm)) continue;
    seen.add(norm);
    clean.push({
      id: String(tab.id || crypto.randomUUID()),
      title: String(tab.title || '').trim() || url,
      url,
      lastVisitedAt: typeof tab.lastVisitedAt === 'number' && tab.lastVisitedAt > 0
        ? (tab.lastVisitedAt < 10_000_000_000 ? Math.round(tab.lastVisitedAt * 1000) : Math.round(tab.lastVisitedAt))
        : Date.now(),
    });
    if (clean.length >= MAX_DEVICE_TABS) break;
  }
  return clean;
}

async function hydrateLegacyScopesIfNeeded(userId: string, env: Env): Promise<void> {
  const legacy = await env.AUTH_DB.prepare('SELECT * FROM user_sync_data WHERE user_id = ?')
    .bind(userId)
    .first<SyncRow>();
  if (!legacy) return;

  if (legacy.bookmarks_json) {
    const existing = await env.AUTH_DB.prepare(
      'SELECT version FROM user_sync_scopes WHERE user_id = ? AND scope = ?'
    )
      .bind(userId, 'bookmarks')
      .first<{ version: number }>();
    if (!existing) {
      await env.AUTH_DB.prepare(
        `INSERT INTO user_sync_scopes (user_id, scope, payload_json, encryption_mode, version, updated_at, updated_by_device_id)
         VALUES (?, 'bookmarks', ?, 'none', ?, ?, 'legacy-v1')`
      )
        .bind(userId, legacy.bookmarks_json, Math.max(1, legacy.version), legacy.updated_at)
        .run();
    }
  }

  if (legacy.settings_json) {
    const existing = await env.AUTH_DB.prepare(
      'SELECT version FROM user_sync_scopes WHERE user_id = ? AND scope = ?'
    )
      .bind(userId, 'settings')
      .first<{ version: number }>();
    if (!existing) {
      await env.AUTH_DB.prepare(
        `INSERT INTO user_sync_scopes (user_id, scope, payload_json, encryption_mode, version, updated_at, updated_by_device_id)
         VALUES (?, 'settings', ?, 'none', ?, ?, 'legacy-v1')`
      )
        .bind(userId, legacy.settings_json, Math.max(1, legacy.version), legacy.updated_at)
        .run();
    }
  }
}

export async function handleSyncV3Pull(
  url: URL,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  await hydrateLegacyScopesIfNeeded(user.id, env);

  const scopesParam = url.searchParams.get('scopes') || 'bookmarks,settings,site_controls,device_tabs';
  const requested = scopesParam
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const excludeDeviceId = (url.searchParams.get('excludeDeviceId') || '').trim();
  const now = Date.now();
  const proActive = await isUserProActive(user.id, env, now);

  const scopeRows = await env.AUTH_DB.prepare('SELECT * FROM user_sync_scopes WHERE user_id = ?')
    .bind(user.id)
    .all<SyncScopeRow>();

  const scopes: Record<string, unknown> = {};
  for (const row of scopeRows.results || []) {
    if (requested.length > 0 && !requested.includes(row.scope)) {
      continue;
    }
    scopes[row.scope] = {
      version: row.version,
      encryptionMode: row.encryption_mode,
      updatedAt: row.updated_at,
      payload: JSON.parse(row.payload_json),
    };
  }

  for (const scopeName of requested) {
    if (VALID_SCOPES.has(scopeName) && !scopes[scopeName]) {
      scopes[scopeName] = {
        version: 0,
        encryptionMode: 'none',
        updatedAt: 0,
        payload: null,
      };
    }
  }

  let remoteDevices: unknown[] = [];
  if (requested.includes('device_tabs')) {
    const devRows = await env.AUTH_DB.prepare(
      'SELECT * FROM user_device_tabs WHERE user_id = ? ORDER BY updated_at DESC'
    )
      .bind(user.id)
      .all<DeviceTabRow>();

    remoteDevices = (devRows.results || [])
      .filter((row) => !excludeDeviceId || row.device_id !== excludeDeviceId)
      .map((row) => ({
        deviceId: row.device_id,
        deviceName: row.device_name,
        platform: row.platform,
        encryptionMode: row.encryption_mode,
        updatedAt: row.updated_at,
        tabs: JSON.parse(row.tabs_json),
      }));
  }

  return jsonResponse(
    {
      ok: true,
      proActive,
      serverTime: now,
      scopes,
      remoteDevices,
    },
    headers
  );
}

export async function handleSyncV3Push(
  request: Request,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  await hydrateLegacyScopesIfNeeded(user.id, env);

  const body = (await request.json().catch(() => ({}))) as {
    deviceId?: string;
    deviceName?: string;
    platform?: string;
    scopes?: Record<string, PushScopeInput>;
    deviceTabs?: IncomingTab[];
  };

  const now = Date.now();
  const deviceId = String(body.deviceId || 'unknown-device').trim().slice(0, 120);
  const deviceName = String(body.deviceName || '卓阅设备').trim().slice(0, 120);
  const platform = String(body.platform || 'web').trim().toLowerCase();

  const scopesInput = body.scopes || {};
  if (Object.prototype.hasOwnProperty.call(scopesInput, 'articles_meta')) {
    const proActive = await isUserProActive(user.id, env, now);
    if (!proActive) {
      return jsonResponse(
        { error: '离线文章同步为卓阅 Pro 专属权益', code: 'PRO_REQUIRED' },
        headers,
        403
      );
    }
  }

  const conflicts: Array<Record<string, unknown>> = [];
  const appliedScopes: Record<string, { version: number; updatedAt: number }> = {};

  for (const [scopeName, input] of Object.entries(scopesInput)) {
    if (!VALID_SCOPES.has(scopeName) || !input || input.payload === undefined) {
      continue;
    }

    const baseVersion = typeof input.baseVersion === 'number' ? input.baseVersion : 0;
    const encryptionMode = input.encryptionMode === 'e2ee-v1' ? 'e2ee-v1' : 'none';
    const existing = await env.AUTH_DB.prepare(
      'SELECT * FROM user_sync_scopes WHERE user_id = ? AND scope = ?'
    )
      .bind(user.id, scopeName)
      .first<SyncScopeRow>();

    const currentVersion = existing?.version || 0;
    if (currentVersion !== baseVersion) {
      conflicts.push({
        scope: scopeName,
        conflict: true,
        currentVersion,
        encryptionMode: existing?.encryption_mode || 'none',
        updatedAt: existing?.updated_at || 0,
        currentPayload: existing ? JSON.parse(existing.payload_json) : null,
      });
      continue;
    }

    const nextVersion = currentVersion + 1;
    const serializedPayload = JSON.stringify(input.payload);
    await env.AUTH_DB.prepare(
      `INSERT INTO user_sync_scopes (user_id, scope, payload_json, encryption_mode, version, updated_at, updated_by_device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, scope) DO UPDATE SET
         payload_json = excluded.payload_json,
         encryption_mode = excluded.encryption_mode,
         version = excluded.version,
         updated_at = excluded.updated_at,
         updated_by_device_id = excluded.updated_by_device_id`
    )
      .bind(user.id, scopeName, serializedPayload, encryptionMode, nextVersion, now, deviceId)
      .run();

    appliedScopes[scopeName] = { version: nextVersion, updatedAt: now };

    if ((scopeName === 'bookmarks' || scopeName === 'settings') && encryptionMode === 'none') {
      const col = scopeName === 'bookmarks' ? 'bookmarks_json' : 'settings_json';
      await env.AUTH_DB.prepare(
        `INSERT INTO user_sync_data (user_id, ${col}, version, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           ${col} = excluded.${col},
           version = excluded.version,
           updated_at = excluded.updated_at`
      )
        .bind(user.id, serializedPayload, nextVersion, now)
        .run();
    }
  }

  let deviceTabsUpdatedAt: number | null = null;
  if (Array.isArray(body.deviceTabs) && deviceId.length > 0) {
    const sanitized = sanitizeTabs(body.deviceTabs);
    await env.AUTH_DB.prepare(
      `INSERT INTO user_device_tabs (user_id, device_id, device_name, platform, tabs_json, encryption_mode, updated_at)
       VALUES (?, ?, ?, ?, ?, 'none', ?)
       ON CONFLICT(user_id, device_id) DO UPDATE SET
         device_name = excluded.device_name,
         platform = excluded.platform,
         tabs_json = excluded.tabs_json,
         updated_at = excluded.updated_at`
    )
      .bind(user.id, deviceId, deviceName, platform, JSON.stringify(sanitized), now)
      .run();
    deviceTabsUpdatedAt = now;
  }

  if (conflicts.length > 0) {
    return jsonResponse(
      {
        ok: false,
        error: 'VERSION_CONFLICT',
        conflicts,
        appliedScopes,
        deviceTabsUpdatedAt,
      },
      headers,
      409
    );
  }

  return jsonResponse(
    {
      ok: true,
      appliedScopes,
      deviceTabsUpdatedAt,
      serverTime: now,
    },
    headers
  );
}

function getBundleBucket(env: Env): R2Bucket | undefined {
  return env.SYNC_BUNDLES || env.AVATARS;
}

export async function handleArticleBundlePut(
  articleIdRaw: string,
  request: Request,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const now = Date.now();
  if (!(await isUserProActive(user.id, env, now))) {
    return jsonResponse({ error: '离线文章同步为卓阅 Pro 专属权益', code: 'PRO_REQUIRED' }, headers, 403);
  }

  const bucket = getBundleBucket(env);
  if (!bucket) {
    return jsonResponse({ error: 'Bundle storage not configured' }, headers, 500);
  }

  const articleId = articleIdRaw.replace(/[^a-zA-Z0-9._-]/g, '');
  if (!articleId) {
    return jsonResponse({ error: 'Invalid article ID' }, headers, 400);
  }

  const buffer = await request.arrayBuffer();
  if (buffer.byteLength === 0 || buffer.byteLength > MAX_ARTICLE_BUNDLE_BYTES) {
    return jsonResponse({ error: 'Article bundle must be between 1B and 5MB' }, headers, 400);
  }

  const digest = await sha256Hex(buffer);
  const r2Key = `articles/${user.id}/${articleId}.json`;

  await bucket.put(r2Key, buffer, {
    httpMetadata: { contentType: 'application/json' },
    customMetadata: { userId: user.id, articleId, sha256: digest },
  });

  await env.AUTH_DB.prepare(
    `INSERT INTO user_article_bundles (user_id, article_id, r2_key, sha256, byte_size, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, article_id) DO UPDATE SET
       r2_key = excluded.r2_key,
       sha256 = excluded.sha256,
       byte_size = excluded.byte_size,
       updated_at = excluded.updated_at`
  )
    .bind(user.id, articleId, r2Key, digest, buffer.byteLength, now)
    .run();

  return jsonResponse({ ok: true, articleId, sha256: digest, byteSize: buffer.byteLength, updatedAt: now }, headers);
}

export async function handleArticleBundleGet(
  articleIdRaw: string,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const bucket = getBundleBucket(env);
  if (!bucket) {
    return jsonResponse({ error: 'Bundle storage not configured' }, headers, 500);
  }

  const articleId = articleIdRaw.replace(/[^a-zA-Z0-9._-]/g, '');
  if (!articleId) {
    return jsonResponse({ error: 'Invalid article ID' }, headers, 400);
  }

  const r2Key = `articles/${user.id}/${articleId}.json`;
  const obj = await bucket.get(r2Key);
  if (!obj) {
    return jsonResponse({ error: 'Article bundle not found' }, headers, 404);
  }

  const responseHeaders = new Headers();
  responseHeaders.set('Access-Control-Allow-Origin', headers['Access-Control-Allow-Origin'] || '*');
  responseHeaders.set('Content-Type', 'application/json');
  responseHeaders.set('ETag', obj.httpEtag);
  return new Response(obj.body, { status: 200, headers: responseHeaders });
}

export async function handleArticleBundleDelete(
  articleIdRaw: string,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  await ensureAuthSyncV2Schema(env);
  const articleId = articleIdRaw.replace(/[^a-zA-Z0-9._-]/g, '');
  if (!articleId) {
    return jsonResponse({ error: 'Invalid article ID' }, headers, 400);
  }

  const r2Key = `articles/${user.id}/${articleId}.json`;
  const bucket = getBundleBucket(env);
  if (bucket) {
    await bucket.delete(r2Key).catch(() => undefined);
  }

  await env.AUTH_DB.prepare('DELETE FROM user_article_bundles WHERE user_id = ? AND article_id = ?')
    .bind(user.id, articleId)
    .run();

  return jsonResponse({ ok: true, deleted: true }, headers);
}
