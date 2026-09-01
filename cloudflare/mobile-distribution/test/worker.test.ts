import { describe, expect, it, vi } from "vitest";
import worker from "../src/worker";

const slug = "zhuobrowser-preview-0123456789abcdef";
const token = "a".repeat(64);
const sourceSha = "1".repeat(40);
const build = {
  source_sha: sourceSha,
  version: "1.0.0",
  build: "1000000",
  status: "uploaded",
  created_at: "2026-09-01 00:00:00",
  updated_at: "2026-09-01 00:00:00",
};
const artifact = {
  name: "ZhuoBrowser.hap",
  object_key: `harmony/${sourceSha}/ZhuoBrowser.hap`,
  sha256: "f".repeat(64),
  bytes: 3,
  content_type: "application/octet-stream",
  created_at: "2026-09-01 00:00:00",
};

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function environment() {
  const get = vi.fn(async (_key: string, options?: R2GetOptions) => {
    const hasRange = options?.range instanceof Headers && options.range.has("range");
    return {
      body: new Blob([hasRange ? "h" : "hap"]).stream(),
      httpEtag: '"etag"',
      size: 3,
      range: hasRange ? { offset: 0, length: 1 } : undefined,
      httpMetadata: { contentType: "application/octet-stream" },
      writeHttpMetadata: (headers: Headers) => headers.set("content-type", "application/octet-stream"),
    } as unknown as R2ObjectBody;
  });
  const put = vi.fn(async (..._args: unknown[]) => null);
  const remove = vi.fn(async (..._args: unknown[]) => null);
  const head = vi.fn<(key: string) => Promise<R2Object | null>>(async (key: string) => ({
    key,
    size: 3,
    customMetadata: { sha256: artifact.sha256 },
    httpMetadata: { contentType: "application/octet-stream" },
  }) as unknown as R2Object);
  const statement = {
    bind: vi.fn(() => statement),
    first: vi.fn(async () => build),
    all: vi.fn(async () => ({ results: [artifact] })),
    run: vi.fn(async () => ({ success: true, meta: { changes: 1 } })),
  };
  const database = {
    prepare: vi.fn(() => statement),
    batch: vi.fn(async () => []),
  } as unknown as D1Database;
  return {
    env: {
      BUILDS: { get, put, head, delete: remove } as unknown as R2Bucket,
      RELEASE_DB: database,
      APP_ID: "zhuobrowser",
      DOWNLOAD_SLUG: slug,
      UPLOAD_TOKEN: token,
    },
    get,
    put,
    head,
    remove,
    database,
  };
}

describe("ZhuoBrowser mobile distribution Worker", () => {
  it("fails closed when deployment configuration is incomplete", async () => {
    const { env } = environment();
    env.DOWNLOAD_SLUG = "replace-with-an-unlisted-download-channel";
    const response = await worker.fetch(new Request("https://example.test/health"), env);
    expect(response.status).toBe(503);
  });

  it("keeps the download surface unlisted", async () => {
    const { env } = environment();
    const response = await worker.fetch(new Request("https://example.test/"), env);
    expect(response.status).toBe(404);
  });

  it("renders the latest retained build with noindex", async () => {
    const { env } = environment();
    const response = await worker.fetch(new Request(`https://example.test/${slug}`), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("x-robots-tag")).toContain("noindex");
    const body = await response.text();
    expect(body).toContain("HarmonyOS 1.0.0 (1000000)");
    expect(body).toContain("ZhuoBrowser.hap");
    expect(body).toContain("AppGallery Connect");
  });

  it("rejects unauthenticated uploads", async () => {
    const { env, put } = environment();
    const response = await worker.fetch(
      new Request(`https://example.test/api/artifacts/${sourceSha}/ZhuoBrowser.hap`, {
        method: "PUT",
        headers: {
          "content-length": "3",
          "x-artifact-version": "1.0.0",
          "x-artifact-build": "1000000",
          "x-artifact-sha256": await sha256("hap"),
        },
        body: "hap",
      }),
      env,
    );
    expect(response.status).toBe(401);
    expect(put).not.toHaveBeenCalled();
  });

  it("checks the payload checksum before immutable storage", async () => {
    const { env, put } = environment();
    const response = await worker.fetch(
      new Request(`https://example.test/api/artifacts/${sourceSha}/ZhuoBrowser.hap`, {
        method: "PUT",
        headers: {
          authorization: `Bearer ${token}`,
          "content-length": "3",
          "x-artifact-version": "1.0.0",
          "x-artifact-build": "1000000",
          "x-artifact-sha256": "0".repeat(64),
        },
        body: "hap",
      }),
      env,
    );
    expect(response.status).toBe(422);
    expect(put).not.toHaveBeenCalled();
  });

  it("stores and records a verified artifact", async () => {
    const { env, head, put, database } = environment();
    const checksum = await sha256("hap");
    head.mockResolvedValueOnce(null).mockResolvedValueOnce({
      key: `harmony/${sourceSha}/ZhuoBrowser.hap`,
      size: 3,
      customMetadata: { sha256: checksum },
      httpMetadata: { contentType: "application/octet-stream" },
    } as unknown as R2Object);
    const response = await worker.fetch(
      new Request(`https://example.test/api/artifacts/${sourceSha}/ZhuoBrowser.hap`, {
        method: "PUT",
        headers: {
          authorization: `Bearer ${token}`,
          "content-length": "3",
          "content-type": "application/octet-stream",
          "x-artifact-version": "1.0.0",
          "x-artifact-build": "1000000",
          "x-artifact-sha256": checksum,
        },
        body: "hap",
      }),
      env,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      status: "uploaded",
      key: `harmony/${sourceSha}/ZhuoBrowser.hap`,
      bytes: 3,
    });
    expect(put).toHaveBeenCalledOnce();
    expect(database.batch).toHaveBeenCalledOnce();
  });

  it("serves retained artifacts with byte ranges", async () => {
    const { env } = environment();
    const response = await worker.fetch(
      new Request(`https://example.test/${slug}/artifacts/harmony/${sourceSha}/ZhuoBrowser.hap`, {
        headers: { range: "bytes=0-0" },
      }),
      env,
    );
    expect(response.status).toBe(206);
    expect(response.headers.get("content-range")).toBe("bytes 0-0/3");
    expect(await response.text()).toBe("h");
  });
});
