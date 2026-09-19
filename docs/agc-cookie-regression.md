# AGC authentication and SPA content regressions

## Verified causes (2026-09-19)

Two independent defects required separate device reproductions.

### Authentication cookie shadowing

The retained tablet stopped at an empty OAuth callback and AGC APIs returned
401. Its cookie store contained fresh `.developer.huawei.com` domain cookies
and older `developer.huawei.com` host-only copies of `authInfo`, `authdata`,
`csrfToken`, and `developer_userinfo`.

The former tablet background persistence code reconstructed every Cookie header
pair with `Path=/; Max-Age=2592000`. Request headers omit Domain, Path, HttpOnly,
SameSite and expiry. Reconstruction changed cookie identity and even exposed
copies of HttpOnly values to scripts. Huawei updated its domain cookies while
stale host copies remained visible first. Removing only the four conflicting
host copies restored the authenticated homepage and application list.

### Destructive static-resource misclassification

After a fresh user login, the navigation header and Vue route advanced while
the homepage remained mounted. Native WebConsole logs recorded `insertBefore`,
`parentNode` and unmount errors. This reopened the navigation acceptance gate.

`TRACKER_URL_PATTERNS` contained `/stat`. Its substring check matched AGC's
`/static/` scripts and images. Cleanup removed live DOM nodes during initial
rendering and broke Vue's retained node references. A fresh-document probe
reproduced the failure. Disabling only the resource-removal query in a second
fresh document restored application-list rendering without exceptions. A full
refresh could hide the defect; refresh-only acceptance was insufficient.

## Repairs

- Use native cookie flushing without changing site-owned attributes or expiry.
- Before the first Web document, expire only known Huawei login host shadows at
  the exact host/root path. Omit Domain so live domain cookies survive; exclude
  private cookies and other origins. Do not repeat this on each tab attachment.
- Remove obsolete history-origin collection and cookie-promotion helpers.
- Require a delimiter after `stat` so `/static/`, `/status/` and `/statistics/`
  resources survive. Synchronize the shared script into iOS and Android assets.
- Retain existing routing behavior; no additional hash workaround was added.

Tablet kernels may omit session cookies from disk. Process restart may require
login; fabricating persistent copies is not a valid workaround.

## Verification

The lifecycle regressions and static-resource regression failed on their prior
implementations and passed after correction. Node regressions pass 84/84.
The release HAP builds, installs and launches on tablet `45P0225509000207`.
Final HAP SHA-256:
`4a350b02689fd8b57f8309177b4e6af665f12a4ec3ce89a86ae31cd9ce5cad03`.

The final entry Hypium run passed 220/220 tests. After the user completed a fresh
login on the final installed package, two native-touch rounds passed all 12
route/content assertions: applications, analysis, users, certificates, projects,
and return to applications. Iframe contents were inspected, not just top-level
navigation labels. Screenshots visibly confirmed each section.

Native background/foreground, toolbar refresh, then back/forward passed. Final
process logs had none of the prior DOM-integrity failures; no conflicting host
authentication cookies returned after backgrounding. Navigation reported no HTTP
errors and one non-blocking site ResizeObserver warning.

An attempted in-memory cookie preservation across installation failed when the
debug connection reset. No credentials were written to disk or restored; final
acceptance used the user's subsequent fresh login. iOS/Android assets were
synchronized but not built or device-tested in this Harmony task.

See `tool/agent_harmony_tests/cases.json` and generated `report.html`.
Local diagnostic artifacts are under `/tmp/zhuo-agc-debug`; no cookie values,
authorization codes or account API payloads are committed.
