export interface Env {
  AUTH_DB: D1Database;
  AVATARS?: R2Bucket;
  APP_ID?: string;
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
  async fetch(request: Request, env: Env): Promise<Response> {
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

      return jsonResponse({ error: 'Not Found' }, corsHeaders, 404);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return jsonResponse({ error: 'Internal Server Error', details: message }, corsHeaders, 500);
    }
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
