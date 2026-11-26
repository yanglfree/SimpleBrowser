import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.ts';
import { setJwksFetchOverrideForTesting } from '../src/jwks.ts';
import { setIapFetchOverrideForTesting } from '../src/pro-entitlement.ts';

function createMemoryD1() {
  const tables = {
    users: new Map(),
    sessions: new Map(),
    user_sync_data: new Map(),
    auth_otp_codes: new Map(),
    auth_rate_limits: new Map(),
    user_identities: new Map(),
    oauth_states: new Map(),
    oauth_tickets: new Map(),
    device_sessions: new Map(),
    user_sync_scopes: new Map(),
    user_device_tabs: new Map(),
    user_pro_bindings: new Map(),
    user_pro_entitlements: new Map(),
    user_article_bundles: new Map(),
  };

  function runSql(sql, params) {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (normalized.startsWith('CREATE TABLE') || normalized.startsWith('CREATE INDEX')) {
      return { results: [], success: true };
    }

    // users
    if (normalized.startsWith('SELECT id FROM users WHERE email = ?')) {
      for (const u of tables.users.values()) {
        if (u.email === params[0]) return { row: { id: u.id } };
      }
      return { row: null };
    }
    if (normalized.startsWith('SELECT * FROM users WHERE email = ?')) {
      for (const u of tables.users.values()) {
        if (u.email === params[0]) return { row: { ...u } };
      }
      return { row: null };
    }
    if (normalized.startsWith('SELECT * FROM users WHERE id = ?')) {
      return { row: tables.users.get(params[0]) ? { ...tables.users.get(params[0]) } : null };
    }
    if (normalized.startsWith('INSERT INTO users')) {
      const [id, email, password_hash, salt, display_name, created_at, updated_at] = params;
      tables.users.set(id, { id, email, password_hash, salt, display_name, avatar_url: null, created_at, updated_at });
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM users WHERE id = ?')) {
      tables.users.delete(params[0]);
      return { success: true };
    }

    // sessions
    if (normalized.startsWith('INSERT INTO sessions')) {
      const [id, user_id, created_at, expires_at] = params;
      tables.sessions.set(id, { id, user_id, created_at, expires_at });
      return { success: true };
    }
    if (normalized.startsWith('SELECT * FROM sessions WHERE id = ? AND expires_at > ?')) {
      const s = tables.sessions.get(params[0]);
      return { row: s && s.expires_at > params[1] ? { ...s } : null };
    }
    if (normalized.startsWith('DELETE FROM sessions WHERE id = ?')) {
      tables.sessions.delete(params[0]);
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM sessions WHERE user_id = ?')) {
      for (const [k, v] of tables.sessions.entries()) {
        if (v.user_id === params[0]) tables.sessions.delete(k);
      }
      return { success: true };
    }

    // device_sessions
    if (normalized.startsWith('INSERT INTO device_sessions')) {
      const [session_id, user_id, device_id, device_name, platform, created_at, last_seen_at, expires_at] = params;
      tables.device_sessions.set(session_id, {
        session_id, user_id, device_id, device_name, platform, created_at, last_seen_at, expires_at,
      });
      return { success: true };
    }
    if (normalized.startsWith('SELECT session_id, device_id, device_name, platform, created_at, last_seen_at, expires_at FROM device_sessions')) {
      const rows = [];
      for (const v of tables.device_sessions.values()) {
        if (v.user_id === params[0] && v.expires_at > params[1]) rows.push({ ...v });
      }
      return { results: rows };
    }
    if (normalized.startsWith('DELETE FROM device_sessions WHERE session_id = ?')) {
      tables.device_sessions.delete(params[0]);
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM device_sessions WHERE user_id = ?')) {
      for (const [k, v] of tables.device_sessions.entries()) {
        if (v.user_id === params[0]) tables.device_sessions.delete(k);
      }
      return { success: true };
    }

    // auth_otp_codes
    if (normalized.startsWith('SELECT created_at FROM auth_otp_codes WHERE email = ?')) {
      const matched = Array.from(tables.auth_otp_codes.values())
        .filter((r) => r.email === params[0])
        .sort((a, b) => b.created_at - a.created_at);
      return { row: matched[0] ? { created_at: matched[0].created_at } : null };
    }
    if (normalized.startsWith('SELECT * FROM auth_otp_codes WHERE email = ? AND expires_at > ?')) {
      const matched = Array.from(tables.auth_otp_codes.values())
        .filter((r) => r.email === params[0] && r.expires_at > params[1])
        .sort((a, b) => b.created_at - a.created_at);
      return { row: matched[0] ? { ...matched[0] } : null };
    }
    if (normalized.startsWith('INSERT INTO auth_otp_codes')) {
      const [id, email, code_hash, salt, expires_at, created_at, request_ip] = params;
      tables.auth_otp_codes.set(id, { id, email, code_hash, salt, attempts: 0, expires_at, created_at, request_ip });
      return { success: true };
    }
    if (normalized.startsWith('UPDATE auth_otp_codes SET attempts = attempts + 1 WHERE id = ?')) {
      const r = tables.auth_otp_codes.get(params[0]);
      if (r) r.attempts += 1;
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM auth_otp_codes WHERE id = ?')) {
      tables.auth_otp_codes.delete(params[0]);
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM auth_otp_codes WHERE email = ?')) {
      for (const [k, v] of tables.auth_otp_codes.entries()) {
        if (v.email === params[0]) tables.auth_otp_codes.delete(k);
      }
      return { success: true };
    }

    // rate limits
    if (normalized.startsWith('SELECT count, window_start FROM auth_rate_limits WHERE bucket_key = ?')) {
      return { row: tables.auth_rate_limits.get(params[0]) || null };
    }
    if (normalized.startsWith('INSERT INTO auth_rate_limits')) {
      tables.auth_rate_limits.set(params[0], { bucket_key: params[0], count: 1, window_start: params[1] });
      return { success: true };
    }
    if (normalized.startsWith('UPDATE auth_rate_limits SET count = count + 1')) {
      const r = tables.auth_rate_limits.get(params[0]);
      if (r) r.count += 1;
      return { success: true };
    }

    // user_identities
    if (normalized.startsWith('SELECT * FROM user_identities WHERE provider = ? AND provider_subject = ?')) {
      const key = `${params[0]}::${params[1]}`;
      return { row: tables.user_identities.get(key) ? { ...tables.user_identities.get(key) } : null };
    }
    if (normalized.startsWith('INSERT INTO user_identities')) {
      const [id, user_id, provider, provider_subject, provider_email, email_verified, profile_json, created_at, updated_at] = params;
      const key = `${provider}::${provider_subject}`;
      const prev = tables.user_identities.get(key);
      tables.user_identities.set(key, {
        id: prev?.id || id,
        user_id,
        provider,
        provider_subject,
        provider_email: provider_email ?? prev?.provider_email ?? null,
        email_verified: Math.max(email_verified, prev?.email_verified ?? 0),
        profile_json,
        created_at: prev?.created_at || created_at,
        updated_at,
      });
      return { success: true };
    }
    if (normalized.startsWith('SELECT provider, provider_email, email_verified, created_at, updated_at FROM user_identities WHERE user_id = ?')) {
      const rows = Array.from(tables.user_identities.values()).filter((r) => r.user_id === params[0]);
      return { results: rows };
    }
    if (normalized.startsWith('DELETE FROM user_identities WHERE user_id = ? AND provider = ?')) {
      for (const [k, v] of tables.user_identities.entries()) {
        if (v.user_id === params[0] && v.provider === params[1]) tables.user_identities.delete(k);
      }
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM user_identities WHERE user_id = ?')) {
      for (const [k, v] of tables.user_identities.entries()) {
        if (v.user_id === params[0]) tables.user_identities.delete(k);
      }
      return { success: true };
    }

    // legacy user_sync_data
    if (normalized.startsWith('SELECT * FROM user_sync_data WHERE user_id = ?')) {
      return { row: tables.user_sync_data.get(params[0]) || null };
    }
    if (normalized.startsWith('SELECT version FROM user_sync_data WHERE user_id = ?')) {
      const r = tables.user_sync_data.get(params[0]);
      return { row: r ? { version: r.version } : null };
    }
    if (normalized.startsWith('INSERT INTO user_sync_data')) {
      const prev = tables.user_sync_data.get(params[0]) || { user_id: params[0], bookmarks_json: null, settings_json: null, version: 0, updated_at: 0 };
      if (normalized.includes('bookmarks_json, settings_json')) {
        tables.user_sync_data.set(params[0], {
          user_id: params[0],
          bookmarks_json: params[1] ?? prev.bookmarks_json,
          settings_json: params[2] ?? prev.settings_json,
          version: params[3],
          updated_at: params[4],
        });
      } else if (normalized.includes('bookmarks_json')) {
        tables.user_sync_data.set(params[0], { ...prev, bookmarks_json: params[1], version: params[2], updated_at: params[3] });
      } else if (normalized.includes('settings_json')) {
        tables.user_sync_data.set(params[0], { ...prev, settings_json: params[1], version: params[2], updated_at: params[3] });
      }
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM user_sync_data WHERE user_id = ?')) {
      tables.user_sync_data.delete(params[0]);
      return { success: true };
    }

    // user_sync_scopes
    if (normalized.startsWith('SELECT version FROM user_sync_scopes WHERE user_id = ? AND scope = ?') ||
        normalized.startsWith('SELECT * FROM user_sync_scopes WHERE user_id = ? AND scope = ?')) {
      return { row: tables.user_sync_scopes.get(`${params[0]}::${params[1]}`) || null };
    }
    if (normalized.startsWith('SELECT * FROM user_sync_scopes WHERE user_id = ?')) {
      const rows = [];
      for (const v of tables.user_sync_scopes.values()) {
        if (v.user_id === params[0]) rows.push({ ...v });
      }
      return { results: rows };
    }
    if (normalized.startsWith('INSERT INTO user_sync_scopes')) {
      if (normalized.includes("'bookmarks'")) {
        const [user_id, payload_json, version, updated_at] = params;
        tables.user_sync_scopes.set(`${user_id}::bookmarks`, {
          user_id, scope: 'bookmarks', payload_json, encryption_mode: 'none', version, updated_at, updated_by_device_id: 'legacy-v1',
        });
      } else if (normalized.includes("'settings'")) {
        const [user_id, payload_json, version, updated_at] = params;
        tables.user_sync_scopes.set(`${user_id}::settings`, {
          user_id, scope: 'settings', payload_json, encryption_mode: 'none', version, updated_at, updated_by_device_id: 'legacy-v1',
        });
      } else {
        const [user_id, scope, payload_json, encryption_mode, version, updated_at, updated_by_device_id] = params;
        tables.user_sync_scopes.set(`${user_id}::${scope}`, {
          user_id, scope, payload_json, encryption_mode, version, updated_at, updated_by_device_id,
        });
      }
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM user_sync_scopes WHERE user_id = ?')) {
      for (const [k, v] of tables.user_sync_scopes.entries()) {
        if (v.user_id === params[0]) tables.user_sync_scopes.delete(k);
      }
      return { success: true };
    }

    // user_device_tabs
    if (normalized.startsWith('INSERT INTO user_device_tabs')) {
      const [user_id, device_id, device_name, platform, tabs_json, updated_at] = params;
      tables.user_device_tabs.set(`${user_id}::${device_id}`, {
        user_id, device_id, device_name, platform, tabs_json, encryption_mode: 'none', updated_at,
      });
      return { success: true };
    }
    if (normalized.startsWith('SELECT * FROM user_device_tabs WHERE user_id = ?')) {
      const rows = Array.from(tables.user_device_tabs.values()).filter((r) => r.user_id === params[0]);
      return { results: rows };
    }
    if (normalized.startsWith('DELETE FROM user_device_tabs WHERE user_id = ?')) {
      for (const [k, v] of tables.user_device_tabs.entries()) {
        if (v.user_id === params[0]) tables.user_device_tabs.delete(k);
      }
      return { success: true };
    }

    // pro bindings & entitlements
    if (normalized.startsWith('SELECT * FROM user_pro_bindings WHERE platform = ? AND install_id = ?')) {
      return { row: tables.user_pro_bindings.get(`${params[0]}::${params[1]}`) || null };
    }
    if (normalized.startsWith('SELECT COUNT(*) as total FROM user_pro_bindings WHERE user_id = ?')) {
      const total = Array.from(tables.user_pro_bindings.values()).filter((r) => r.user_id === params[0]).length;
      return { row: { total } };
    }
    if (normalized.startsWith('INSERT INTO user_pro_bindings')) {
      const [id, user_id, platform, install_id, bound_at, last_verified_at] = params;
      const key = `${platform}::${install_id}`;
      const prev = tables.user_pro_bindings.get(key);
      tables.user_pro_bindings.set(key, {
        id: prev?.id || id,
        user_id,
        platform,
        install_id,
        bound_at: prev && prev.user_id === user_id ? prev.bound_at : bound_at,
        last_verified_at,
        rebind_count: prev && prev.user_id !== user_id ? prev.rebind_count + 1 : (prev?.rebind_count || 0),
      });
      return { success: true };
    }
    if (normalized.startsWith('SELECT * FROM user_pro_bindings WHERE user_id = ?')) {
      const rows = Array.from(tables.user_pro_bindings.values()).filter((r) => r.user_id === params[0]);
      return { results: rows };
    }
    if (normalized.startsWith('DELETE FROM user_pro_bindings WHERE user_id = ?')) {
      for (const [k, v] of tables.user_pro_bindings.entries()) {
        if (v.user_id === params[0]) tables.user_pro_bindings.delete(k);
      }
      return { success: true };
    }
    if (normalized.startsWith('SELECT * FROM user_pro_entitlements WHERE user_id = ?')) {
      return { row: tables.user_pro_entitlements.get(params[0]) || null };
    }
    if (normalized.startsWith('INSERT INTO user_pro_entitlements')) {
      const [user_id, plan, product_id, expires_at, source_platform, verified_at, updated_at] = params;
      tables.user_pro_entitlements.set(user_id, {
        user_id, active: 1, scope: 'pro', plan, product_id, expires_at, source_platform, verified_at, updated_at,
      });
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM user_pro_entitlements WHERE user_id = ?')) {
      tables.user_pro_entitlements.delete(params[0]);
      return { success: true };
    }

    // user_article_bundles
    if (normalized.startsWith('INSERT INTO user_article_bundles')) {
      const [user_id, article_id, r2_key, sha256, byte_size, updated_at] = params;
      tables.user_article_bundles.set(`${user_id}::${article_id}`, {
        user_id, article_id, r2_key, sha256, byte_size, updated_at,
      });
      return { success: true };
    }
    if (normalized.startsWith('SELECT r2_key FROM user_article_bundles WHERE user_id = ?')) {
      const rows = Array.from(tables.user_article_bundles.values())
        .filter((r) => r.user_id === params[0])
        .map((r) => ({ r2_key: r.r2_key }));
      return { results: rows };
    }
    if (normalized.startsWith('DELETE FROM user_article_bundles WHERE user_id = ? AND article_id = ?')) {
      tables.user_article_bundles.delete(`${params[0]}::${params[1]}`);
      return { success: true };
    }
    if (normalized.startsWith('DELETE FROM user_article_bundles WHERE user_id = ?')) {
      for (const [k, v] of tables.user_article_bundles.entries()) {
        if (v.user_id === params[0]) tables.user_article_bundles.delete(k);
      }
      return { success: true };
    }

    throw new Error(`Unhandled SQL in test mock: ${normalized}`);
  }

  return {
    tables,
    prepare(sql) {
      let bound = [];
      const stmt = {
        bind(...args) {
          bound = args;
          return stmt;
        },
        async first() {
          const out = runSql(sql, bound);
          return out.row ?? null;
        },
        async all() {
          const out = runSql(sql, bound);
          return { results: out.results ?? [], success: true };
        },
        async run() {
          const out = runSql(sql, bound);
          return { success: out.success ?? true };
        },
      };
      return stmt;
    },
  };
}

function createMemoryR2() {
  const objects = new Map();
  return {
    objects,
    async put(key, value) {
      const buf = value instanceof ArrayBuffer ? new Uint8Array(value) : new Uint8Array(value);
      objects.set(key, {
        body: buf,
        httpEtag: `"etag-${key}"`,
        writeHttpMetadata() {},
      });
    },
    async get(key) {
      return objects.get(key) || null;
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

function base64Url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let bin = '';
  for (let i = 0; i < bytes.byteLength; i += 1) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function createTestSignedJwt(claims) {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify']
  );
  const publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  publicJwk.kid = 'test-key-1';
  publicJwk.use = 'sig';
  publicJwk.alg = 'RS256';

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: 'test-key-1' }));
  const payload = base64Url(JSON.stringify(claims));
  const signingInput = new TextEncoder().encode(`${header}.${payload}`);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, signingInput);
  return {
    jwt: `${header}.${payload}.${base64Url(sig)}`,
    jwks: { keys: [publicJwk] },
  };
}

function makeEnv() {
  return {
    AUTH_DB: createMemoryD1(),
    AVATARS: createMemoryR2(),
    WALLPAPERS: createMemoryR2(),
    ALLOW_DEV_OTP_ECHO: 'true',
    IAP_GATEWAY_URL: 'https://gateway.youdroid.top',
  };
}

async function api(env, path, init = {}, cfCountry = 'CN') {
  const req = new Request(`https://auth.zhuobrowser.youdroid.top${path}`, init);
  req.cf = { country: cfCountry };
  return await worker.fetch(req, env);
}

test('provider discovery enforces Mainland China Google Sign-In gating', async () => {
  const env = makeEnv();
  const cnResp = await api(env, '/api/auth/providers?platform=harmony&region=CN', {}, 'CN');
  const cnBody = await cnResp.json();
  assert.equal(cnBody.googleAllowed, false);
  assert.equal(cnBody.providers.some((p) => p.id === 'huawei'), true);
  assert.equal(cnBody.providers.some((p) => p.id === 'google'), false);

  const hkResp = await api(env, '/api/auth/providers?platform=ios&region=HK', {}, 'CN');
  const hkBody = await hkResp.json();
  assert.equal(hkBody.googleAllowed, true);
  assert.equal(hkBody.providers.some((p) => p.id === 'apple'), true);
  assert.equal(hkBody.providers.some((p) => p.id === 'google'), true);
});

test('Email OTP + Apple + Huawei native login auto-link by verified email and protect sole identity', async () => {
  const env = makeEnv();

  // 1. Send OTP & verify
  const sendResp = await api(env, '/api/auth/otp/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'youdroid@example.com' }),
  });
  assert.equal(sendResp.status, 200);
  const { devCode } = await sendResp.json();
  assert.match(devCode, /^\d{6}$/);

  const verifyResp = await api(env, '/api/auth/otp/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: 'youdroid@example.com',
      code: devCode,
      deviceId: 'ios-1',
      deviceName: 'iPhone 17 Pro',
      platform: 'ios',
    }),
  });
  assert.equal(verifyResp.status, 200);
  const verifyData = await verifyResp.json();
  assert.equal(verifyData.user.email, 'youdroid@example.com');
  assert.equal(verifyData.identities.length, 1);

  // Cannot unlink sole identity
  const failUnlink = await api(env, '/api/auth/identities/email', {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${verifyData.token}` },
  });
  assert.equal(failUnlink.status, 400);

  // 2. Native Apple login with same verified email auto-links to same user
  const exp = Math.floor(Date.now() / 1000) + 300;
  const appleToken = await createTestSignedJwt({
    iss: 'https://appleid.apple.com',
    aud: 'com.youdroid.zhuobrowser',
    sub: 'apple-sub-001',
    email: 'youdroid@example.com',
    email_verified: true,
    exp,
  });

  setJwksFetchOverrideForTesting(async () => new Response(JSON.stringify(appleToken.jwks), { status: 200 }));
  try {
    const appleResp = await api(env, '/api/auth/oauth/native', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        provider: 'apple',
        idToken: appleToken.jwt,
        deviceId: 'mac-1',
        deviceName: 'MacBook Pro',
        platform: 'macos',
      }),
    });
    assert.equal(appleResp.status, 200);
    const appleData = await appleResp.json();
    assert.equal(appleData.user.id, verifyData.user.id);
    assert.equal(appleData.identities.length, 2);

    // Now unlinking apple succeeds
    const unlinkOk = await api(env, '/api/auth/identities/apple', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${appleData.token}` },
    });
    assert.equal(unlinkOk.status, 200);
    const unlinkBody = await unlinkOk.json();
    assert.equal(unlinkBody.identities.length, 1);
  } finally {
    setJwksFetchOverrideForTesting(null);
  }
});

test('v3 scoped CAS sync detects version conflicts, migrates v1 data, and filters private tabs', async () => {
  const env = makeEnv();
  const regResp = await api(env, '/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'sync@example.com', password: 'password123', displayName: 'Syncer' }),
  });
  const { token, user } = await regResp.json();

  // Seed legacy v1 data
  await api(env, '/api/sync/push', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      bookmarks: [{ title: 'Legacy', url: 'https://legacy.test' }],
      settings: { searchEngine: 'google', updatedAt: 1760000000000 },
    }),
  });

  // Pull v3 hydrates legacy version=1
  const pull1 = await api(env, '/api/sync/v3/pull?scopes=bookmarks,settings', {
    headers: { Authorization: `Bearer ${token}` },
  });
  const pull1Body = await pull1.json();
  assert.equal(pull1Body.scopes.bookmarks.version, 1);

  // Device A pushes with baseVersion 1 -> succeeds (version 2) + uploads deviceTabs with private tab filtered out
  const pushA = await api(env, '/api/sync/v3/push', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      deviceId: 'mac-1',
      deviceName: 'Mac Studio',
      platform: 'macos',
      scopes: {
        bookmarks: { baseVersion: 1, payload: { version: 3, folders: [], items: [{ id: '1', url: 'https://a.test' }], tombstones: [] } },
      },
      deviceTabs: [
        { id: 't1', title: 'Public', url: 'https://swift.org', isPrivate: false },
        { id: 't2', title: 'Private', url: 'https://secret.test', isPrivate: true },
        { id: 't3', title: 'Home', url: 'zhuo://home', isPrivate: false },
      ],
    }),
  });
  assert.equal(pushA.status, 200);
  const pushABody = await pushA.json();
  assert.equal(pushABody.appliedScopes.bookmarks.version, 2);

  // Device B pushes stale baseVersion 1 -> 409 VERSION_CONFLICT
  const pushB = await api(env, '/api/sync/v3/push', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      deviceId: 'harmony-1',
      deviceName: 'Mate 70',
      platform: 'harmony',
      scopes: {
        bookmarks: { baseVersion: 1, payload: { version: 3, folders: [], items: [{ id: '2', url: 'https://b.test' }], tombstones: [] } },
      },
    }),
  });
  assert.equal(pushB.status, 409);
  const pushBBody = await pushB.json();
  assert.equal(pushBBody.error, 'VERSION_CONFLICT');
  assert.equal(pushBBody.conflicts[0].currentVersion, 2);

  // Harmony pulls device_tabs excluding itself -> sees only non-private Mac tab
  const pullTabs = await api(env, '/api/sync/v3/pull?scopes=device_tabs&excludeDeviceId=harmony-1', {
    headers: { Authorization: `Bearer ${token}` },
  });
  const pullTabsBody = await pullTabs.json();
  assert.equal(pullTabsBody.remoteDevices.length, 1);
  assert.equal(pullTabsBody.remoteDevices[0].tabs.length, 1);
  assert.equal(pullTabsBody.remoteDevices[0].tabs[0].url, 'https://swift.org');
  assert.ok(user.id);
});

test('Pro entitlement binding unlocks cross-platform Pro article sync & deletes cleanly', async () => {
  const env = makeEnv();
  const regResp = await api(env, '/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'pro@example.com', password: 'password123', displayName: 'ProUser' }),
  });
  const { token, user } = await regResp.json();

  // Without Pro, pushing articles_meta or bundle returns 403 PRO_REQUIRED
  const deniedPush = await api(env, '/api/sync/v3/push', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      deviceId: 'ios-1',
      platform: 'ios',
      scopes: { articles_meta: { baseVersion: 0, payload: { articles: [], tombstones: [] } } },
    }),
  });
  assert.equal(deniedPush.status, 403);

  // Bind HarmonyOS Pro install_id
  setIapFetchOverrideForTesting(async () => new Response(JSON.stringify({
    entitlement: {
      active: true,
      scope: 'pro',
      plan: 'yearly',
      product_id: 'com.youdroid.zhuobrowser.pro_yearly',
      expires_at: Date.now() + 30 * 86400 * 1000,
    },
  }), { status: 200 }));

  try {
    const bindResp = await api(env, '/api/pro/bind', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ platform: 'harmony', installId: 'zb-harmony-install-123' }),
    });
    assert.equal(bindResp.status, 200);
    const bindData = await bindResp.json();
    assert.equal(bindData.entitlement.active, true);
    assert.equal(bindData.entitlement.plan, 'yearly');

    // Now Pro article bundle upload + meta push succeed
    const putBundle = await api(env, '/api/sync/v3/articles/art-1/bundle', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ html: '<p>Hello</p>', markdown: 'Hello' }),
    });
    assert.equal(putBundle.status, 200);

    const getBundle = await api(env, '/api/sync/v3/articles/art-1/bundle', {
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(getBundle.status, 200);
    const bundleJson = await getBundle.json();
    assert.equal(bundleJson.markdown, 'Hello');

    // Permanent delete removes user, bindings, scopes, and R2 objects
    const delResp = await api(env, '/api/auth/account', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(delResp.status, 200);
    assert.equal(env.AUTH_DB.tables.users.has(user.id), false);
    assert.equal(env.AVATARS.objects.size, 0);
  } finally {
    setIapFetchOverrideForTesting(null);
  }
});

test('send_email Workers binding delivers OTP without third-party API secrets', async () => {
  const sentMessages = [];
  const env = {
    ...makeEnv(),
    ALLOW_DEV_OTP_ECHO: 'false',
    EMAIL_FROM: 'noreply@auth-mail.youdroid.top',
    EMAIL_FROM_NAME: '卓阅浏览器',
    EMAIL: {
      async send(msg) {
        sentMessages.push(msg);
        return { messageId: 'cf-msg-001' };
      },
    },
  };

  const providersResp = await api(env, '/api/auth/providers?platform=ios&region=CN');
  assert.equal(providersResp.status, 200);
  const providersData = await providersResp.json();
  const otpProvider = providersData.providers.find((p) => p.id === 'email_otp');
  assert.equal(otpProvider?.configured, true);

  const sendResp = await api(env, '/api/auth/otp/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'otp-binding@example.com' }),
  });
  assert.equal(sendResp.status, 200);
  const sendData = await sendResp.json();
  assert.equal(sendData.ok, true);
  assert.equal(sendData.devCode, undefined);
  assert.equal(sentMessages.length, 1);
  assert.equal(sentMessages[0].from.email, 'noreply@auth-mail.youdroid.top');
  assert.deepEqual(sentMessages[0].to, ['otp-binding@example.com']);
  assert.match(sentMessages[0].text, /\d{6}/);
  assert.match(sentMessages[0].html, /<strong>\d{6}<\/strong>/);
});
