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

## Follow-up: general compatibility hardening

The delimiter fix above was only the initial repair. The shared tracker script
also removed ordinary `soundtrack`, `pixel-art`, and `phishing-awareness`
resources, and replaced every `sendBeacon` call with a fake successful return.

The follow-up removes both interventions entirely. Existing native network
rules remain responsible for blocking requests. The script retains its JSON
contract for platform callers but reports zero observations: loaded resources
are neither removed nor counted as blocked. Keyword classification remains
only for categorizing requests that the native blocker already blocked.
Unmatched requests now follow the browser's normal behavior; this intentionally
removes blanket beacon suppression, not the native filtering rules. No new
claim is made that native filtering blocks every tracker on every platform.

Regression coverage checks benign keyword URLs, framework-owned nodes, repeated
injection, beacon payload identity, receiver, false returns and native exceptions.
Shared assets are synchronized for HarmonyOS, iOS and Android.

Follow-up validation: 84 Node tests passed and the signed HarmonyOS release HAP
built successfully; the entry Hypium test task also passed. A fresh iframe in the connected tablet's ArkWeb retained
its native beacon function and DOM nodes across two executions of the new
script. This is script-level device evidence, not installed-package acceptance.
The tablet still runs the preceding accepted package to retain its AGC login;
the new package has not been installed. iOS/Android were not built or run.
The existing AGC navigation acceptance recorded above belongs to the preceding
fix. Reader-mode DOM restoration and hash-click compensation remain separate
follow-up audit items.
