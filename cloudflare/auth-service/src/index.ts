export interface Env {
  AUTH_DB: D1Database;
  AVATARS?: R2Bucket;
  WALLPAPERS?: R2Bucket;
  APP_ID?: string;
}

interface BingWallpaperRow {
  end_date: string;
  start_date: string;
  title: string;
  copyright: string;
  copyright_link: string | null;
  url_base: string;
  full_r2_key: string;
  thumb_r2_key: string;
  byte_size: number;
  thumb_byte_size: number;
  mkt: string;
  created_at: number;
  updated_at: number;
}

interface BingUpstreamImage {
  startdate?: string;
  enddate?: string;
  url?: string;
  urlbase?: string;
  copyright?: string;
  copyrightlink?: string;
  title?: string;
}

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  salt: string;
  display_name: string;
  avatar_url?: string | null;
  created_at: number;
  updated_at: number;
}

interface SessionRow {
  id: string;
  user_id: string;
  created_at: number;
  expires_at: number;
}

interface SyncRow {
  user_id: string;
  bookmarks_json: string | null;
  settings_json: string | null;
  version: number;
  updated_at: number;
}

// 30 days in milliseconds
const SESSION_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;

export default {
  async fetch(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '*';

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const corsHeaders = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Content-Type': 'application/json',
    };

    try {
      if (url.pathname === '/' || url.pathname === '/health') {
        return jsonResponse({ status: 'ok', service: 'ZhuoBrowser Auth & Sync Service', timestamp: Date.now() }, corsHeaders);
      }

      // Authentication routes
      if (url.pathname === '/api/auth/register' && request.method === 'POST') {
        return await handleRegister(request, env, corsHeaders);
      }

      if (url.pathname === '/api/auth/login' && request.method === 'POST') {
        return await handleLogin(request, env, corsHeaders);
      }

      if (url.pathname === '/api/auth/me' && request.method === 'GET') {
        const user = await authenticateRequest(request, env);
        if (!user) {
          return jsonResponse({ error: 'Unauthorized' }, corsHeaders, 401);
        }
        return jsonResponse({ ok: true, user: sanitizeUser(user) }, corsHeaders);
      }

      if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
        await handleLogout(request, env);
        return jsonResponse({ ok: true, message: 'Logged out successfully' }, corsHeaders);
      }

      // Cloud Sync routes
      if (url.pathname === '/api/sync/pull' && request.method === 'GET') {
        const user = await authenticateRequest(request, env);
        if (!user) {
          return jsonResponse({ error: 'Unauthorized' }, corsHeaders, 401);
        }
        return await handleSyncPull(user.id, env, corsHeaders);
      }

      if (url.pathname === '/api/sync/push' && request.method === 'POST') {
        const user = await authenticateRequest(request, env);
        if (!user) {
          return jsonResponse({ error: 'Unauthorized' }, corsHeaders, 401);
        }
        return await handleSyncPush(request, user.id, env, corsHeaders);
      }

      // User Avatar routes
      if (url.pathname === '/api/user/avatar' && request.method === 'POST') {
        const user = await authenticateRequest(request, env);
        if (!user) {
          return jsonResponse({ error: 'Unauthorized' }, corsHeaders, 401);
        }
        return await handleUploadAvatar(request, user, env, corsHeaders);
      }

      if (url.pathname.startsWith('/api/user/avatar/') && request.method === 'GET') {
        const pathParts = url.pathname.split('/');
        const targetUserId = pathParts[4];
        if (!targetUserId) {
          return jsonResponse({ error: 'User ID required' }, corsHeaders, 400);
        }
        return await handleGetAvatar(targetUserId, env, corsHeaders);
      }

      // Bing Daily Wallpaper Archive routes
      if (url.pathname === '/api/wallpapers/bing' && request.method === 'GET') {
        return await handleListBingWallpapers(url, env, corsHeaders, ctx);
      }

      if (url.pathname === '/api/wallpapers/bing/sync' && request.method === 'POST') {
        return await handleSyncBingWallpapers(env, corsHeaders);
      }

      if (url.pathname.startsWith('/api/wallpapers/bing/') && (request.method === 'GET' || request.method === 'HEAD')) {
        const pathParts = url.pathname.split('/');
        const targetDate = pathParts[4];
        if (!targetDate) {
          return jsonResponse({ error: 'Wallpaper date required' }, corsHeaders, 400);
        }
        return await handleGetBingWallpaperImage(targetDate, url, env, corsHeaders, ctx);
      }

      return jsonResponse({ error: 'Not Found' }, corsHeaders, 404);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return jsonResponse({ error: 'Internal Server Error', details: message }, corsHeaders, 500);
    }
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      (async () => {
        await ensureBingWallpapersSchema(env);
        await syncBingMetadataFromUpstream(env, true);
        await archivePendingBingImagesToR2(env, 16);
      })()
    );
  },
};

// Handlers
async function handleRegister(request: Request, env: Env, headers: Record<string, string>): Promise<Response> {
  const body = (await request.json().catch(() => ({}))) as {
    email?: string;
    password?: string;
    displayName?: string;
  };

  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';
  const displayName = (body.displayName || '').trim() || email.split('@')[0] || 'User';

  if (!email || !email.includes('@') || email.length > 120) {
    return jsonResponse({ error: 'Invalid email address' }, headers, 400);
  }

  if (password.length < 6 || password.length > 128) {
    return jsonResponse({ error: 'Password must be between 6 and 128 characters' }, headers, 400);
  }

  // Check if email already registered
  const existing = await env.AUTH_DB.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
  if (existing) {
    return jsonResponse({ error: 'Email already registered' }, headers, 409);
  }

  const userId = crypto.randomUUID();
  const salt = generateSalt();
  const passwordHash = await hashPassword(password, salt);
  const now = Date.now();

  await env.AUTH_DB.prepare(
    'INSERT INTO users (id, email, password_hash, salt, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  )
    .bind(userId, email, passwordHash, salt, displayName, now, now)
    .run();

  const token = generateToken();
  const expiresAt = now + SESSION_LIFETIME_MS;

  await env.AUTH_DB.prepare('INSERT INTO sessions (id, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)')
    .bind(token, userId, now, expiresAt)
    .run();

  return jsonResponse(
    {
      ok: true,
      token,
      user: {
        id: userId,
        email,
        displayName,
        avatarUrl: null,
      },
    },
    headers,
    201
  );
}

async function handleLogin(request: Request, env: Env, headers: Record<string, string>): Promise<Response> {
  const body = (await request.json().catch(() => ({}))) as {
    email?: string;
    password?: string;
  };

  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';

  if (!email || !password) {
    return jsonResponse({ error: 'Email and password are required' }, headers, 400);
  }

  const user = await env.AUTH_DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first<UserRow>();
  if (!user) {
    return jsonResponse({ error: 'Invalid email or password' }, headers, 401);
  }

  const computedHash = await hashPassword(password, user.salt);
  if (computedHash !== user.password_hash) {
    return jsonResponse({ error: 'Invalid email or password' }, headers, 401);
  }

  const token = generateToken();
  const now = Date.now();
  const expiresAt = now + SESSION_LIFETIME_MS;

  await env.AUTH_DB.prepare('INSERT INTO sessions (id, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)')
    .bind(token, user.id, now, expiresAt)
    .run();

  return jsonResponse(
    {
      ok: true,
      token,
      user: sanitizeUser(user),
    },
    headers
  );
}

async function handleLogout(request: Request, env: Env): Promise<void> {
  const token = extractBearerToken(request);
  if (token) {
    await env.AUTH_DB.prepare('DELETE FROM sessions WHERE id = ?').bind(token).run();
  }
}

async function handleSyncPull(userId: string, env: Env, headers: Record<string, string>): Promise<Response> {
  const data = await env.AUTH_DB.prepare('SELECT * FROM user_sync_data WHERE user_id = ?')
    .bind(userId)
    .first<SyncRow>();

  if (!data) {
    return jsonResponse(
      {
        ok: true,
        bookmarks: [],
        settings: null,
        version: 0,
        updatedAt: 0,
      },
      headers
    );
  }

  return jsonResponse(
    {
      ok: true,
      bookmarks: data.bookmarks_json ? JSON.parse(data.bookmarks_json) : [],
      settings: data.settings_json ? JSON.parse(data.settings_json) : null,
      version: data.version,
      updatedAt: data.updated_at,
    },
    headers
  );
}

async function handleSyncPush(request: Request, userId: string, env: Env, headers: Record<string, string>): Promise<Response> {
  const body = (await request.json().catch(() => ({}))) as {
    bookmarks?: unknown;
    settings?: unknown;
  };

  const bookmarksJson = body.bookmarks ? JSON.stringify(body.bookmarks) : null;
  const settingsJson = body.settings ? JSON.stringify(body.settings) : null;
  const now = Date.now();

  const existing = await env.AUTH_DB.prepare('SELECT version FROM user_sync_data WHERE user_id = ?')
    .bind(userId)
    .first<{ version: number }>();

  const nextVersion = (existing?.version || 0) + 1;

  await env.AUTH_DB.prepare(
    `INSERT INTO user_sync_data (user_id, bookmarks_json, settings_json, version, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       bookmarks_json = COALESCE(excluded.bookmarks_json, user_sync_data.bookmarks_json),
       settings_json = COALESCE(excluded.settings_json, user_sync_data.settings_json),
       version = excluded.version,
       updated_at = excluded.updated_at`
  )
    .bind(userId, bookmarksJson, settingsJson, nextVersion, now)
    .run();

  return jsonResponse(
    {
      ok: true,
      version: nextVersion,
      updatedAt: now,
    },
    headers
  );
}

async function handleUploadAvatar(
  request: Request,
  user: UserRow,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  if (!env.AVATARS) {
    return jsonResponse({ error: 'Avatar storage not configured' }, headers, 500);
  }

  const contentType = request.headers.get('Content-Type') || '';
  const allowedMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
  const mime = allowedMimeTypes.find((m) => contentType.toLowerCase().includes(m));

  if (!mime) {
    return jsonResponse(
      { error: 'Invalid content type. Only JPEG, PNG, WebP, or GIF are supported.' },
      headers,
      400
    );
  }

  const arrayBuffer = await request.arrayBuffer();
  const MAX_SIZE = 2 * 1024 * 1024;
  if (arrayBuffer.byteLength === 0) {
    return jsonResponse({ error: 'Image body cannot be empty' }, headers, 400);
  }
  if (arrayBuffer.byteLength > MAX_SIZE) {
    return jsonResponse({ error: 'Image file too large (max 2MB)' }, headers, 400);
  }

  const ext = mime === 'image/png' ? 'png' : mime === 'image/webp' ? 'webp' : mime === 'image/gif' ? 'gif' : 'jpg';
  const objectKey = `avatars/${user.id}.${ext}`;

  await env.AVATARS.put(objectKey, arrayBuffer, {
    httpMetadata: {
      contentType: mime,
      cacheControl: 'public, max-age=86400',
    },
  });

  const now = Date.now();
  const avatarUrl = `/api/user/avatar/${user.id}?v=${now}`;

  await env.AUTH_DB.prepare('UPDATE users SET avatar_url = ?, updated_at = ? WHERE id = ?')
    .bind(avatarUrl, now, user.id)
    .run();

  const updatedUser: UserRow = {
    ...user,
    avatar_url: avatarUrl,
    updated_at: now,
  };

  return jsonResponse(
    {
      ok: true,
      avatarUrl,
      user: sanitizeUser(updatedUser),
    },
    headers
  );
}

async function handleGetAvatar(
  userId: string,
  env: Env,
  headers: Record<string, string>
): Promise<Response> {
  if (!env.AVATARS) {
    return jsonResponse({ error: 'Avatar storage not configured' }, headers, 500);
  }

  const safeUserId = userId.replace(/[^a-zA-Z0-9_-]/g, '');
  if (!safeUserId) {
    return jsonResponse({ error: 'Invalid user ID' }, headers, 400);
  }

  const extensions = ['jpg', 'png', 'webp', 'gif'];
  let object: R2ObjectBody | null = null;

  for (const ext of extensions) {
    const key = `avatars/${safeUserId}.${ext}`;
    const obj = await env.AVATARS.get(key);
    if (obj) {
      object = obj;
      break;
    }
  }

  if (!object) {
    return jsonResponse({ error: 'Avatar not found' }, headers, 404);
  }

  const responseHeaders = new Headers();
  object.writeHttpMetadata(responseHeaders);
  responseHeaders.set('Access-Control-Allow-Origin', headers['Access-Control-Allow-Origin'] || '*');
  responseHeaders.set('Cache-Control', 'public, max-age=86400');
  responseHeaders.set('ETag', object.httpEtag);
  if (!responseHeaders.has('Content-Type')) {
    responseHeaders.set('Content-Type', 'image/jpeg');
  }

  return new Response(object.body, {
    status: 200,
    headers: responseHeaders,
  });
}

// Helpers
async function authenticateRequest(request: Request, env: Env): Promise<UserRow | null> {
  const token = extractBearerToken(request);
  if (!token) return null;

  const now = Date.now();
  const session = await env.AUTH_DB.prepare('SELECT * FROM sessions WHERE id = ? AND expires_at > ?')
    .bind(token, now)
    .first<SessionRow>();

  if (!session) return null;

  const user = await env.AUTH_DB.prepare('SELECT * FROM users WHERE id = ?').bind(session.user_id).first<UserRow>();
  return user || null;
}

function extractBearerToken(request: Request): string | null {
  const authHeader = request.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  return authHeader.slice(7).trim();
}

function sanitizeUser(user: UserRow) {
  return {
    id: user.id,
    email: user.email,
    displayName: user.display_name,
    avatarUrl: user.avatar_url || null,
    createdAt: user.created_at,
  };
}

function jsonResponse(data: unknown, headers: Record<string, string>, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers,
  });
}

function generateSalt(): string {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, '0')).join('');
}

function generateToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, '0')).join('');
}

async function hashPassword(password: string, salt: string): Promise<string> {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey('raw', enc.encode(password), { name: 'PBKDF2' }, false, [
    'deriveBits',
  ]);

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

// ============================================================================
// Bing Daily Wallpaper Archive & R2 Storage Handlers
// ============================================================================

async function ensureBingWallpapersSchema(env: Env): Promise<void> {
  await env.AUTH_DB.prepare(
    `CREATE TABLE IF NOT EXISTS bing_wallpapers (
      end_date TEXT PRIMARY KEY,
      start_date TEXT NOT NULL,
      title TEXT NOT NULL,
      copyright TEXT NOT NULL,
      copyright_link TEXT,
      url_base TEXT NOT NULL,
      full_r2_key TEXT NOT NULL,
      thumb_r2_key TEXT NOT NULL,
      byte_size INTEGER NOT NULL DEFAULT 0,
      thumb_byte_size INTEGER NOT NULL DEFAULT 0,
      mkt TEXT NOT NULL DEFAULT 'zh-CN',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`
  ).run();
}

function getBeijingDateYYYYMMDD(nowMs = Date.now()): string {
  const beijingDate = new Date(nowMs + 8 * 60 * 60 * 1000);
  const y = beijingDate.getUTCFullYear();
  const m = String(beijingDate.getUTCMonth() + 1).padStart(2, '0');
  const d = String(beijingDate.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}`;
}

function isValidJpeg(bytes: Uint8Array): boolean {
  return (
    bytes.byteLength >= 4 &&
    bytes.byteLength <= 20 * 1024 * 1024 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[bytes.byteLength - 2] === 0xff &&
    bytes[bytes.byteLength - 1] === 0xd9
  );
}

function normalizeBingUrlBase(item: BingUpstreamImage): string | null {
  if (item.urlbase && /^\/th\?id=OHR\.[A-Za-z0-9._%-]+$/.test(item.urlbase)) {
    return item.urlbase;
  }
  if (item.url) {
    const match = item.url.match(/^(\/th\?id=OHR\.[A-Za-z0-9._%-]+)_(?:1920x1080|UHD)\b/);
    if (match) {
      return match[1];
    }
  }
  return null;
}

async function fetchBingArchiveBatch(idx: number, count: number): Promise<BingUpstreamImage[]> {
  const archiveUrl = `https://www.bing.com/HPImageArchive.aspx?format=js&idx=${idx}&n=${count}&mkt=zh-CN`;
  const resp = await fetch(archiveUrl, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'ZhuoBrowser-WallpaperArchiver/1.0',
    },
  });
  if (!resp.ok) {
    return [];
  }
  const data = (await resp.json().catch(() => ({}))) as { images?: BingUpstreamImage[] };
  return Array.isArray(data.images) ? data.images : [];
}

async function syncBingMetadataFromUpstream(env: Env, includeOlderBatch = false): Promise<number> {
  const firstBatch = await fetchBingArchiveBatch(0, 8);
  const secondBatch = includeOlderBatch ? await fetchBingArchiveBatch(7, 8) : [];
  const allItems = [...firstBatch, ...secondBatch];

  const seenDates = new Set<string>();
  const now = Date.now();
  let upserted = 0;

  for (const item of allItems) {
    const endDate = (item.enddate || '').trim();
    const startDate = (item.startdate || endDate).trim();
    const urlBase = normalizeBingUrlBase(item);
    if (!/^\d{8}$/.test(endDate) || !urlBase || seenDates.has(endDate)) {
      continue;
    }
    seenDates.add(endDate);

    const title = (item.title || '').trim() || `必应每日壁纸 ${endDate}`;
    const copyright = (item.copyright || '').trim();
    const copyrightLink = (item.copyrightlink || '').trim() || null;
    const fullR2Key = `bing/zh-CN/${endDate}_1920x1080.jpg`;
    const thumbR2Key = `bing/zh-CN/${endDate}_400x240.jpg`;

    await env.AUTH_DB.prepare(
      `INSERT INTO bing_wallpapers (
        end_date, start_date, title, copyright, copyright_link,
        url_base, full_r2_key, thumb_r2_key, mkt, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'zh-CN', ?, ?)
      ON CONFLICT(end_date) DO UPDATE SET
        start_date = excluded.start_date,
        title = excluded.title,
        copyright = excluded.copyright,
        copyright_link = excluded.copyright_link,
        url_base = excluded.url_base,
        updated_at = excluded.updated_at`
    )
      .bind(endDate, startDate, title, copyright, copyrightLink, urlBase, fullR2Key, thumbR2Key, now, now)
      .run();

    upserted += 1;
  }

  return upserted;
}

async function archiveSingleBingVariantToR2(
  row: BingWallpaperRow,
  variant: 'full' | 'thumb',
  env: Env
): Promise<Uint8Array | null> {
  const bucket = env.WALLPAPERS || env.AVATARS;
  const suffix = variant === 'thumb' ? '400x240' : '1920x1080';
  const r2Key = variant === 'thumb' ? row.thumb_r2_key : row.full_r2_key;
  const upstreamUrl = `https://www.bing.com${row.url_base}_${suffix}.jpg`;

  const resp = await fetch(upstreamUrl, {
    headers: {
      Accept: 'image/jpeg',
      'User-Agent': 'ZhuoBrowser-WallpaperArchiver/1.0',
    },
  });
  if (!resp.ok) {
    return null;
  }

  const buffer = await resp.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  if (!isValidJpeg(bytes)) {
    return null;
  }

  if (bucket) {
    await bucket.put(r2Key, bytes, {
      httpMetadata: {
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000, immutable',
      },
      customMetadata: {
        endDate: row.end_date,
        title: row.title,
        variant,
      },
    });
  }

  const now = Date.now();
  if (variant === 'thumb') {
    await env.AUTH_DB.prepare('UPDATE bing_wallpapers SET thumb_byte_size = ?, updated_at = ? WHERE end_date = ?')
      .bind(bytes.byteLength, now, row.end_date)
      .run();
  } else {
    await env.AUTH_DB.prepare('UPDATE bing_wallpapers SET byte_size = ?, updated_at = ? WHERE end_date = ?')
      .bind(bytes.byteLength, now, row.end_date)
      .run();
  }

  return bytes;
}

async function archivePendingBingImagesToR2(env: Env, maxRows = 8): Promise<number> {
  const pending = await env.AUTH_DB.prepare(
    'SELECT * FROM bing_wallpapers WHERE byte_size = 0 OR thumb_byte_size = 0 ORDER BY end_date DESC LIMIT ?'
  )
    .bind(maxRows)
    .all<BingWallpaperRow>();

  const rows = pending.results || [];
  let archivedCount = 0;

  for (const row of rows) {
    if (row.thumb_byte_size === 0) {
      const thumbBytes = await archiveSingleBingVariantToR2(row, 'thumb', env);
      if (thumbBytes) archivedCount += 1;
    }
    if (row.byte_size === 0) {
      const fullBytes = await archiveSingleBingVariantToR2(row, 'full', env);
      if (fullBytes) archivedCount += 1;
    }
  }

  return archivedCount;
}

async function handleListBingWallpapers(
  url: URL,
  env: Env,
  headers: Record<string, string>,
  ctx?: ExecutionContext
): Promise<Response> {
  await ensureBingWallpapersSchema(env);

  const limit = Math.min(90, Math.max(1, parseInt(url.searchParams.get('limit') || '30', 10) || 30));
  const offset = Math.max(0, parseInt(url.searchParams.get('offset') || '0', 10) || 0);

  const stats = await env.AUTH_DB.prepare(
    'SELECT COUNT(*) as total, MAX(end_date) as latest_date, SUM(CASE WHEN byte_size = 0 OR thumb_byte_size = 0 THEN 1 ELSE 0 END) as pending_r2 FROM bing_wallpapers'
  ).first<{ total: number; latest_date: string | null; pending_r2: number }>();

  const totalBefore = stats?.total || 0;
  const latestDate = stats?.latest_date || '';
  const todayBeijing = getBeijingDateYYYYMMDD();

  if (totalBefore < 14 || latestDate < todayBeijing) {
    await syncBingMetadataFromUpstream(env, totalBefore < 14);
    if (ctx) {
      ctx.waitUntil(archivePendingBingImagesToR2(env, 8));
    } else {
      await archivePendingBingImagesToR2(env, 2);
    }
  } else if ((stats?.pending_r2 || 0) > 0 && ctx) {
    ctx.waitUntil(archivePendingBingImagesToR2(env, 6));
  }

  const rowsResult = await env.AUTH_DB.prepare(
    'SELECT * FROM bing_wallpapers ORDER BY end_date DESC LIMIT ? OFFSET ?'
  )
    .bind(limit, offset)
    .all<BingWallpaperRow>();

  const countAfter = await env.AUTH_DB.prepare('SELECT COUNT(*) as total FROM bing_wallpapers').first<{
    total: number;
  }>();

  const rows = rowsResult.results || [];
  const wallpapers = rows.map((row) => ({
    date: row.end_date,
    startDate: row.start_date,
    title: row.title,
    copyright: row.copyright,
    copyrightLink: row.copyright_link,
    imageUrl: `/api/wallpapers/bing/${row.end_date}?variant=full`,
    thumbnailUrl: `/api/wallpapers/bing/${row.end_date}?variant=thumb`,
    bingImageUrl: `https://www.bing.com${row.url_base}_1920x1080.jpg`,
    bingThumbnailUrl: `https://www.bing.com${row.url_base}_400x240.jpg`,
    byteSize: row.byte_size,
    thumbByteSize: row.thumb_byte_size,
  }));

  return jsonResponse(
    {
      ok: true,
      wallpapers,
      total: countAfter?.total || wallpapers.length,
    },
    headers
  );
}

async function handleSyncBingWallpapers(env: Env, headers: Record<string, string>): Promise<Response> {
  await ensureBingWallpapersSchema(env);
  const syncedMetadata = await syncBingMetadataFromUpstream(env, true);
  const archivedImages = await archivePendingBingImagesToR2(env, 16);
  const countRow = await env.AUTH_DB.prepare('SELECT COUNT(*) as total FROM bing_wallpapers').first<{
    total: number;
  }>();

  return jsonResponse(
    {
      ok: true,
      syncedMetadata,
      archivedImages,
      total: countRow?.total || 0,
    },
    headers
  );
}

async function handleGetBingWallpaperImage(
  targetDateParam: string,
  url: URL,
  env: Env,
  headers: Record<string, string>,
  ctx?: ExecutionContext
): Promise<Response> {
  await ensureBingWallpapersSchema(env);

  const variant: 'full' | 'thumb' = url.searchParams.get('variant') === 'thumb' ? 'thumb' : 'full';
  let row: BingWallpaperRow | null = null;

  if (targetDateParam === 'latest' || targetDateParam === 'today') {
    row = await env.AUTH_DB.prepare('SELECT * FROM bing_wallpapers ORDER BY end_date DESC LIMIT 1').first<BingWallpaperRow>();
    if (!row) {
      await syncBingMetadataFromUpstream(env, true);
      row = await env.AUTH_DB.prepare('SELECT * FROM bing_wallpapers ORDER BY end_date DESC LIMIT 1').first<BingWallpaperRow>();
    }
  } else {
    const cleanDate = targetDateParam.replace(/[^0-9]/g, '');
    if (!/^\d{8}$/.test(cleanDate)) {
      return jsonResponse({ error: 'Invalid date format. Expected YYYYMMDD.' }, headers, 400);
    }
    row = await env.AUTH_DB.prepare('SELECT * FROM bing_wallpapers WHERE end_date = ?')
      .bind(cleanDate)
      .first<BingWallpaperRow>();
    if (!row) {
      await syncBingMetadataFromUpstream(env, true);
      row = await env.AUTH_DB.prepare('SELECT * FROM bing_wallpapers WHERE end_date = ?')
        .bind(cleanDate)
        .first<BingWallpaperRow>();
    }
  }

  if (!row) {
    return jsonResponse({ error: 'Wallpaper not found for specified date' }, headers, 404);
  }

  const bucket = env.WALLPAPERS || env.AVATARS;
  const r2Key = variant === 'thumb' ? row.thumb_r2_key : row.full_r2_key;

  if (bucket) {
    const cachedObj = await bucket.get(r2Key);
    if (cachedObj) {
      const responseHeaders = new Headers();
      cachedObj.writeHttpMetadata(responseHeaders);
      responseHeaders.set('Access-Control-Allow-Origin', headers['Access-Control-Allow-Origin'] || '*');
      responseHeaders.set('Cache-Control', 'public, max-age=31536000, immutable');
      responseHeaders.set('ETag', cachedObj.httpEtag);
      responseHeaders.set('X-Wallpaper-Date', row.end_date);
      if (!responseHeaders.has('Content-Type')) {
        responseHeaders.set('Content-Type', 'image/jpeg');
      }
      return new Response(cachedObj.body, {
        status: 200,
        headers: responseHeaders,
      });
    }
  }

  // Lazy fetch from Bing and persist into R2
  const archivedBytes = await archiveSingleBingVariantToR2(row, variant, env);
  if (!archivedBytes) {
    return jsonResponse({ error: 'Upstream wallpaper image unavailable' }, headers, 502);
  }

  if (ctx && ((variant === 'thumb' && row.byte_size === 0) || (variant === 'full' && row.thumb_byte_size === 0))) {
    const otherVariant: 'full' | 'thumb' = variant === 'thumb' ? 'full' : 'thumb';
    ctx.waitUntil(archiveSingleBingVariantToR2(row, otherVariant, env));
  }

  return new Response(archivedBytes, {
    status: 200,
    headers: {
      'Access-Control-Allow-Origin': headers['Access-Control-Allow-Origin'] || '*',
      'Content-Type': 'image/jpeg',
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Wallpaper-Date': row.end_date,
    },
  });
}
