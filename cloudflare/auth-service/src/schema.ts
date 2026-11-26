import type { Env } from './types.ts';

const initializedDbs = new WeakSet<D1Database>();

const V2_DDL_STATEMENTS: string[] = [
  `CREATE TABLE IF NOT EXISTS auth_otp_codes (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    request_ip TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_auth_otp_email_created ON auth_otp_codes(email, created_at DESC)`,
  `CREATE TABLE IF NOT EXISTS auth_rate_limits (
    bucket_key TEXT PRIMARY KEY,
    count INTEGER NOT NULL,
    window_start INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS user_identities (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_subject TEXT NOT NULL,
    provider_email TEXT,
    email_verified INTEGER NOT NULL DEFAULT 0,
    profile_json TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(provider, provider_subject)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_user_identities_user_id ON user_identities(user_id)`,
  `CREATE TABLE IF NOT EXISTS oauth_states (
    state TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    platform TEXT NOT NULL,
    client_redirect_uri TEXT NOT NULL,
    code_verifier TEXT NOT NULL,
    link_user_id TEXT,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS oauth_tickets (
    ticket TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    session_token TEXT NOT NULL,
    is_new_user INTEGER NOT NULL DEFAULT 0,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS device_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_device_sessions_user_id ON device_sessions(user_id)`,
  `CREATE TABLE IF NOT EXISTS user_sync_scopes (
    user_id TEXT NOT NULL,
    scope TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    encryption_mode TEXT NOT NULL DEFAULT 'none',
    version INTEGER NOT NULL DEFAULT 1,
    updated_at INTEGER NOT NULL,
    updated_by_device_id TEXT,
    PRIMARY KEY (user_id, scope)
  )`,
  `CREATE TABLE IF NOT EXISTS user_device_tabs (
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    tabs_json TEXT NOT NULL,
    encryption_mode TEXT NOT NULL DEFAULT 'none',
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, device_id)
  )`,
  `CREATE TABLE IF NOT EXISTS user_pro_bindings (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    platform TEXT NOT NULL,
    install_id TEXT NOT NULL,
    bound_at INTEGER NOT NULL,
    last_verified_at INTEGER NOT NULL,
    rebind_count INTEGER NOT NULL DEFAULT 0,
    UNIQUE(platform, install_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_user_pro_bindings_user_id ON user_pro_bindings(user_id)`,
  `CREATE TABLE IF NOT EXISTS user_pro_entitlements (
    user_id TEXT PRIMARY KEY,
    active INTEGER NOT NULL,
    scope TEXT NOT NULL,
    plan TEXT,
    product_id TEXT,
    expires_at INTEGER NOT NULL,
    source_platform TEXT,
    verified_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS user_article_bundles (
    user_id TEXT NOT NULL,
    article_id TEXT NOT NULL,
    r2_key TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    byte_size INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, article_id)
  )`,
];

export async function ensureAuthSyncV2Schema(env: Env): Promise<void> {
  if (initializedDbs.has(env.AUTH_DB)) {
    return;
  }
  for (const sql of V2_DDL_STATEMENTS) {
    await env.AUTH_DB.prepare(sql).run();
  }
  initializedDbs.add(env.AUTH_DB);
}
