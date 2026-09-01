interface DistributionEnv {
  BUILDS: R2Bucket;
  RELEASE_DB: D1Database;
  APP_ID: string;
  DOWNLOAD_SLUG: string;
  UPLOAD_TOKEN: string;
}

interface ArtifactMetadata {
  sourceSha: string;
  version: string;
  build: string;
  name: string;
  key: string;
  sha256: string;
  bytes: number;
  contentType: string;
}

interface BuildRow {
  source_sha: string;
  version: string;
  build: string;
  status: string;
  created_at: string;
  updated_at: string;
}

interface ArtifactRow {
  name: string;
  object_key: string;
  sha256: string;
  bytes: number;
  content_type: string;
  created_at: string;
}

const maximumArtifactBytes = 100 * 1024 * 1024;
const serviceName = "zhuobrowser-mobile-distribution";

function validSourceSha(value: string): boolean {
  return /^[a-f0-9]{40}$/.test(value);
}

function validArtifactName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._+-]{0,159}$/.test(value);
}

function configurationIsValid(env: DistributionEnv): boolean {
  return (
    env.APP_ID === "zhuobrowser" &&
    /^[A-Za-z0-9_-]{20,}$/.test(env.DOWNLOAD_SLUG) &&
    !env.DOWNLOAD_SLUG.startsWith("replace-") &&
    env.UPLOAD_TOKEN.length >= 32
  );
}

async function tokensMatch(candidate: string, expected: string): Promise<boolean> {
  if (!candidate || !expected) return false;
  const encoder = new TextEncoder();
  const [candidateHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(candidate)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const candidateBytes = new Uint8Array(candidateHash);
  const expectedBytes = new Uint8Array(expectedHash);
  let difference = 0;
  for (let index = 0; index < candidateBytes.length; index += 1) {
    difference |= (candidateBytes[index] ?? 0) ^ (expectedBytes[index] ?? 0);
  }
  return difference === 0;
}

async function authorized(request: Request, env: DistributionEnv): Promise<boolean> {
  const authorization = request.headers.get("authorization") ?? "";
  const candidate = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : "";
  return tokensMatch(candidate, env.UPLOAD_TOKEN);
}

function toHex(value: ArrayBuffer): string {
  return Array.from(new Uint8Array(value), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function privateHeaders(contentType: string): Headers {
  return new Headers({
    "cache-control": "private, no-store, no-transform",
    "content-type": contentType,
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-robots-tag": "noindex, nofollow, noarchive",
  });
}

async function recordArtifact(env: DistributionEnv, artifact: ArtifactMetadata): Promise<void> {
  await env.RELEASE_DB.batch([
    env.RELEASE_DB.prepare(`
      INSERT INTO builds (app, platform, source_sha, version, build, status)
      VALUES (?, 'harmony', ?, ?, ?, 'uploaded')
      ON CONFLICT (app, platform, source_sha, build) DO UPDATE SET
        version = excluded.version,
        status = CASE WHEN builds.status = 'revoked' THEN builds.status ELSE excluded.status END,
        updated_at = CURRENT_TIMESTAMP
    `).bind(env.APP_ID, artifact.sourceSha, artifact.version, artifact.build),
    env.RELEASE_DB.prepare(`
      INSERT INTO artifacts (app, platform, source_sha, build, name, object_key, sha256, bytes, content_type)
      VALUES (?, 'harmony', ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (app, platform, source_sha, build, name) DO UPDATE SET
        object_key = excluded.object_key,
        sha256 = excluded.sha256,
        bytes = excluded.bytes,
        content_type = excluded.content_type
    `).bind(
      env.APP_ID,
      artifact.sourceSha,
      artifact.build,
      artifact.name,
      artifact.key,
      artifact.sha256,
      artifact.bytes,
      artifact.contentType,
    ),
  ]);
}

async function uploadArtifact(request: Request, env: DistributionEnv, pathname: string): Promise<Response> {
  if (!(await authorized(request, env))) return new Response("Unauthorized", { status: 401 });
  const parts = pathname.slice("/api/artifacts/".length).split("/");
  const [sourceSha, name] = parts;
  const version = request.headers.get("x-artifact-version") ?? "";
  const build = request.headers.get("x-artifact-build") ?? "";
  const expectedSha256 = (request.headers.get("x-artifact-sha256") ?? "").toLowerCase();
  const contentLength = Number(request.headers.get("content-length"));
  if (
    parts.length !== 2 || !validSourceSha(sourceSha ?? "") || !validArtifactName(name ?? "") ||
    !/^\d+\.\d+\.\d+$/.test(version) || !/^[1-9]\d*$/.test(build) ||
    !/^[a-f0-9]{64}$/.test(expectedSha256) || !Number.isSafeInteger(contentLength) ||
    contentLength <= 0 || contentLength > maximumArtifactBytes
  ) {
    return new Response("Invalid artifact metadata or payload", { status: 422 });
  }

  const bytes = await request.arrayBuffer();
  if (bytes.byteLength !== contentLength) return new Response("Artifact byte count mismatch", { status: 422 });
  const actualSha256 = toHex(await crypto.subtle.digest("SHA-256", bytes));
  if (actualSha256 !== expectedSha256) return new Response("Artifact checksum mismatch", { status: 422 });

  const key = `harmony/${sourceSha}/${name}`;
  const existing = await env.BUILDS.head(key);
  if (existing && (existing.customMetadata?.sha256 !== actualSha256 || existing.size !== bytes.byteLength)) {
    return new Response("Immutable artifact already exists with different metadata", { status: 409 });
  }
  if (!existing) {
    await env.BUILDS.put(key, bytes, {
      httpMetadata: { contentType: request.headers.get("content-type") ?? "application/octet-stream" },
      customMetadata: { sha256: actualSha256, version, build, sourceSha: sourceSha ?? "", platform: "harmony" },
    });
  }
  const stored = await env.BUILDS.head(key);
  if (!stored || stored.size !== bytes.byteLength || stored.customMetadata?.sha256 !== actualSha256) {
    if (!existing) await env.BUILDS.delete(key);
    return new Response("Artifact storage verification failed", { status: 502 });
  }
  await recordArtifact(env, {
    sourceSha: sourceSha ?? "",
    version,
    build,
    name: name ?? "",
    key,
    sha256: actualSha256,
    bytes: stored.size,
    contentType: stored.httpMetadata?.contentType ?? "application/octet-stream",
  });
  return Response.json({ status: "uploaded", key, sha256: actualSha256, bytes: stored.size, idempotent: Boolean(existing) });
}

async function artifactsForBuild(
  env: DistributionEnv,
  sourceSha: string,
  build?: string,
): Promise<ArtifactRow[]> {
  const query = build
    ? `SELECT name, object_key, sha256, bytes, content_type, created_at FROM artifacts
       WHERE app = ? AND platform = 'harmony' AND source_sha = ? AND build = ? ORDER BY name`
    : `SELECT name, object_key, sha256, bytes, content_type, created_at FROM artifacts
       WHERE app = ? AND platform = 'harmony' AND source_sha = ? ORDER BY name`;
  const statement = env.RELEASE_DB.prepare(query);
  const result = build
    ? await statement.bind(env.APP_ID, sourceSha, build).all<ArtifactRow>()
    : await statement.bind(env.APP_ID, sourceSha).all<ArtifactRow>();
  return result.results ?? [];
}

async function buildStatus(env: DistributionEnv, sourceSha: string): Promise<Response> {
  if (!validSourceSha(sourceSha)) return new Response("Not found", { status: 404 });
  const build = await env.RELEASE_DB.prepare(`
    SELECT source_sha, version, build, status, created_at, updated_at
    FROM builds WHERE app = ? AND platform = 'harmony' AND source_sha = ?
    ORDER BY updated_at DESC LIMIT 1
  `).bind(env.APP_ID, sourceSha).first<BuildRow>();
  if (!build) return new Response("Not found", { status: 404 });
  const artifacts = await artifactsForBuild(env, sourceSha, build.build);
  return Response.json(
    { app: env.APP_ID, platform: "harmony", sourceSha, ...build, artifacts },
    { headers: privateHeaders("application/json; charset=utf-8") },
  );
}

function contentRange(object: R2ObjectBody): { value: string; length: number } | null {
  if (!object.range) return null;
  const range = object.range as { offset?: number; length?: number; suffix?: number };
  if (typeof range.suffix === "number") {
    const length = Math.min(range.suffix, object.size);
    return { value: `bytes ${object.size - length}-${object.size - 1}/${object.size}`, length };
  }
  const offset = range.offset ?? 0;
  const length = range.length ?? object.size - offset;
  if (!Number.isFinite(offset) || !Number.isFinite(length) || length <= 0) return null;
  return { value: `bytes ${offset}-${offset + length - 1}/${object.size}`, length };
}

async function objectResponse(request: Request, env: DistributionEnv, key: string, filename: string): Promise<Response> {
  const hasRange = request.headers.has("range");
  const object = hasRange ? await env.BUILDS.get(key, { range: request.headers }) : await env.BUILDS.get(key);
  if (!object || !("body" in object)) return new Response("Not found", { status: 404 });
  const range = hasRange ? contentRange(object) : null;
  const headers = privateHeaders(object.httpMetadata?.contentType ?? "application/octet-stream");
  object.writeHttpMetadata(headers);
  headers.set("content-length", String(range?.length ?? object.size));
  headers.set("accept-ranges", "bytes");
  headers.set("etag", object.httpEtag);
  headers.set("content-disposition", `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`);
  if (range) headers.set("content-range", range.value);
  return new Response(request.method === "HEAD" ? null : object.body, { status: range ? 206 : 200, headers });
}

function escapeHtml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

async function downloadPage(origin: string, env: DistributionEnv): Promise<Response> {
  const build = await env.RELEASE_DB.prepare(`
    SELECT source_sha, version, build, status, created_at, updated_at
    FROM builds WHERE app = ? AND platform = 'harmony' AND status = 'uploaded'
    ORDER BY created_at DESC LIMIT 1
  `).bind(env.APP_ID).first<BuildRow>();
  const artifacts = build ? await artifactsForBuild(env, build.source_sha, build.build) : [];
  const links = artifacts.map((artifact) => {
    const href = `${origin}/${env.DOWNLOAD_SLUG}/artifacts/harmony/${build?.source_sha}/${encodeURIComponent(artifact.name)}`;
    return `<li><a href="${escapeHtml(href)}">${escapeHtml(artifact.name)}</a> <small>${artifact.bytes} bytes · ${escapeHtml(artifact.sha256)}</small></li>`;
  }).join("");
  const release = build
    ? `<p>HarmonyOS ${escapeHtml(build.version)} (${escapeHtml(build.build)})</p><ul>${links}</ul>`
    : "<p>尚无已验证制品。</p>";
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>卓阅浏览器测试制品</title><style>body{font:16px system-ui;max-width:760px;margin:4rem auto;padding:0 1.25rem;line-height:1.6}a{color:#1263d6}small{display:block;overflow-wrap:anywhere;color:#666}li{margin:1rem 0}</style></head><body><main><h1>卓阅浏览器测试制品</h1>${release}<p>AppGallery Connect 上传、审核和发布仍由维护者手动执行。</p></main></body></html>`;
  const headers = privateHeaders("text/html; charset=utf-8");
  headers.set("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
  return new Response(html, { headers });
}

export default {
  async fetch(request: Request, env: DistributionEnv): Promise<Response> {
    if (!configurationIsValid(env)) return new Response("Distribution is not configured", { status: 503 });
    const url = new URL(request.url);
    if (url.pathname === "/health") return Response.json({ status: "ok", service: serviceName });
    if (request.method === "PUT" && url.pathname.startsWith("/api/artifacts/")) {
      return uploadArtifact(request, env, url.pathname);
    }

    const basePath = `/${env.DOWNLOAD_SLUG}`;
    if (url.pathname !== basePath && !url.pathname.startsWith(`${basePath}/`)) {
      return new Response("Not found", { status: 404, headers: privateHeaders("text/plain; charset=utf-8") });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { allow: "GET, HEAD" } });
    }
    if (url.pathname === basePath || url.pathname === `${basePath}/`) return downloadPage(url.origin, env);

    const statusPrefix = `${basePath}/builds/harmony/`;
    if (url.pathname.startsWith(statusPrefix)) return buildStatus(env, url.pathname.slice(statusPrefix.length));

    const artifactPrefix = `${basePath}/artifacts/harmony/`;
    if (url.pathname.startsWith(artifactPrefix)) {
      const [sourceSha, encodedName, ...extra] = url.pathname.slice(artifactPrefix.length).split("/");
      if (extra.length || !validSourceSha(sourceSha ?? "")) return new Response("Not found", { status: 404 });
      let name: string;
      try {
        name = decodeURIComponent(encodedName ?? "");
      } catch {
        return new Response("Not found", { status: 404 });
      }
      if (!validArtifactName(name)) return new Response("Not found", { status: 404 });
      return objectResponse(request, env, `harmony/${sourceSha}/${name}`, name);
    }
    return new Response("Not found", { status: 404, headers: privateHeaders("text/plain; charset=utf-8") });
  },
};
