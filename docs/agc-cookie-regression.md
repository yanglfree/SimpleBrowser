# AGC blank callback and stale content regression

## Verified cause (2026-09-19)

On the retained Harmony tablet, AGC stopped at an empty OAuth callback. The
homepage APIs returned 401. The cookie store contained both fresh
`.developer.huawei.com` domain cookies and older `developer.huawei.com` host-only
copies of `authInfo`, `authdata`, `csrfToken`, and `developer_userinfo`.

The former tablet background persistence code fetched a Cookie request header
and recreated every pair with `Path=/; Max-Age=2592000`. A request header has no
Domain, Path, HttpOnly, SameSite, expiry, or session metadata. Reconstructing it
changed cookie identity and even made copies of HttpOnly values script-readable.
Huawei's login library updated domain cookies while stale host copies remained
visible first, so the page used stale authentication/CSRF data. Deleting only
these four host copies restored the homepage and the real APP/service list.
The diagnostic did not require changing routing or clearing all browsing data.

## Repair

- Background and page-end persistence use the native cookie-store flush only.
- Before the first Web document, expire the known Huawei login host shadows at
  the exact host and root path. Omit Domain so live domain cookies survive.
  Private cookies and other origins are excluded. Include the associated
  state, return URL, region and team fields owned by Huawei's domain-cookie API.
- Do not repeat cleanup when another Web controller attaches during login.
- Remove the obsolete history-origin collection and cookie-promotion helpers.

Tablet kernels may omit session cookies when persisting to disk. A process
restart can therefore require login again. Cookie expiry and security attributes
must remain site-owned; preserving login by fabricating persistent copies is
not a valid workaround.

## Verification and remaining gate

Two new lifecycle regressions failed on the previous implementation, then passed
with the repair. The final Node suite passed 83 tests; the entry Hypium suite
passed 220 tests. The final release HAP built, installed and launched on the
connected tablet. Its SHA-256 is
`dbda03f4cd7dc12c7f957cb78b4732ae45488f2dec9538f3c7fda425d3279b8b`.

The final installed build renders the normal Huawei login page after restart.
Authenticated section switching, refresh and background recovery remain blocked
on the user completing login. The earlier successful cookie differential is
root-cause evidence, not a substitute for final-build acceptance.

See `tool/agent_harmony_tests/cases.json` and its generated `report.html`.
Diagnostic artifacts are local under `/tmp/zhuo-agc-debug`; no cookie values,
authorization codes or account API payloads are committed.
