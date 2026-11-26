export interface JwkKey extends JsonWebKey {
  kid?: string;
  alg?: string;
  use?: string;
  kty: string;
}

export interface VerifiedOidcClaims {
  iss: string;
  sub: string;
  aud: string | string[];
  exp: number;
  iat?: number;
  email?: string;
  email_verified?: boolean | string;
  name?: string;
  picture?: string;
  nonce?: string;
}

export interface VerifyOidcOptions {
  idToken: string;
  jwksUri: string;
  expectedIssuers: string[];
  expectedAudiences: string[];
  expectedNonce?: string;
  nowSeconds?: number;
}

interface JwksCacheEntry {
  keys: JwkKey[];
  fetchedAt: number;
}

const jwksCache = new Map<string, JwksCacheEntry>();
const JWKS_TTL_MS = 10 * 60 * 1000;

let customFetchImpl: typeof fetch | null = null;

export function setJwksFetchOverrideForTesting(fn: typeof fetch | null): void {
  customFetchImpl = fn;
  jwksCache.clear();
}

function decodeBase64UrlBytes(segment: string): Uint8Array {
  const padded = segment.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (segment.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeBase64UrlJson<T>(segment: string): T {
  const bytes = decodeBase64UrlBytes(segment);
  const text = new TextDecoder().decode(bytes);
  return JSON.parse(text) as T;
}

async function fetchJwksKeys(jwksUri: string, forceRefresh = false): Promise<JwkKey[]> {
  const cached = jwksCache.get(jwksUri);
  const now = Date.now();
  if (!forceRefresh && cached && now - cached.fetchedAt < JWKS_TTL_MS) {
    return cached.keys;
  }

  const fetcher = customFetchImpl ?? fetch;
  const resp = await fetcher(jwksUri, {
    headers: { Accept: 'application/json' },
  });
  if (!resp.ok) {
    throw new Error(`Failed to fetch JWKS (${resp.status})`);
  }
  const body = (await resp.json()) as { keys?: JwkKey[] };
  if (!Array.isArray(body.keys)) {
    throw new Error('Invalid JWKS payload');
  }
  jwksCache.set(jwksUri, { keys: body.keys, fetchedAt: now });
  return body.keys;
}

export async function verifyOIDCToken(options: VerifyOidcOptions): Promise<VerifiedOidcClaims> {
  const parts = options.idToken.split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed JWT');
  }
  const [headerB64, payloadB64, sigB64] = parts;
  const header = decodeBase64UrlJson<{ alg?: string; kid?: string }>(headerB64);
  if (header.alg !== 'RS256') {
    throw new Error(`Unsupported JWT algorithm: ${String(header.alg)}`);
  }

  const claims = decodeBase64UrlJson<VerifiedOidcClaims>(payloadB64);
  const nowSec = options.nowSeconds ?? Math.floor(Date.now() / 1000);

  if (typeof claims.exp !== 'number' || claims.exp <= nowSec - 60) {
    throw new Error('JWT token expired');
  }
  if (!claims.sub || typeof claims.sub !== 'string') {
    throw new Error('JWT missing subject');
  }
  if (!options.expectedIssuers.includes(claims.iss)) {
    throw new Error(`Invalid JWT issuer: ${claims.iss}`);
  }

  if (options.expectedAudiences.length > 0) {
    const audList = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    const matched = audList.some((a) => options.expectedAudiences.includes(a));
    if (!matched) {
      throw new Error('JWT audience mismatch');
    }
  }

  if (options.expectedNonce && claims.nonce !== options.expectedNonce) {
    throw new Error('JWT nonce mismatch');
  }

  let keys = await fetchJwksKeys(options.jwksUri, false);
  let matchedKey = keys.find((k) => (!header.kid || k.kid === header.kid) && k.kty === 'RSA');
  if (!matchedKey) {
    keys = await fetchJwksKeys(options.jwksUri, true);
    matchedKey = keys.find((k) => (!header.kid || k.kid === header.kid) && k.kty === 'RSA');
  }
  if (!matchedKey) {
    throw new Error('Matching JWKS signing key not found');
  }

  const cryptoKey = await crypto.subtle.importKey(
    'jwk',
    matchedKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );

  const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signatureBytes = decodeBase64UrlBytes(sigB64);
  const sigCopy = new Uint8Array(signatureBytes.byteLength);
  sigCopy.set(signatureBytes);

  const verified = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    sigCopy.buffer,
    signingInput
  );
  if (!verified) {
    throw new Error('JWT signature verification failed');
  }

  return claims;
}
