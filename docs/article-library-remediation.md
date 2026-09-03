# Article library remediation

## Requirement and tracking

Date: 2026-09-03. Scope: the user-approved remediation of the Pro article library.
The original report described undiscoverable capture entry points and silent failures,
including a WeChat article displayed as `Article extraction failed`.

Cyclar project: Browser (BRO), `7bce7c27-9eca-4f8e-842b-7adde138451f`.
Issue synchronization is **pending**: the available native MCP credential exposes
read-only tools; no create/update issue capability was available. This document is
the local handoff, not a substitute for the required Cyclar issue. Proposed issue:
"Complete reliable Pro article capture, offline reading and recovery".

## Delivered behavior

- Save the current page from the browser menu or reader toolbar. Add a URL directly
  in the library using normal text-field paste, then explicitly press Save. Existing
  system-share/external-open capture continues to use the same save pipeline.
- Pro gates new captures and retries. Private tabs cannot be captured. Previously
  saved articles remain readable and exportable without an active Pro entitlement.
- Decode both ArkWeb string-result encoding and plain browser JSON. Validate the
  snapshot, wait for stable readable content, and bound stalled script evaluation.
  Short semantic articles and real lazy-image URLs are supported; the shared
  WeChat long-article extraction fixture remains covered.
- Display saving, complete, partial, extraction failure, page-changed and storage
  failure outcomes. Load errors and pending-load timeouts no longer remain silent.
  Failed rows are actionable: open source, retry, or confirm deletion.
- Serialize save/delete mutations and commit immutable content versions with the
  metadata transaction. Failed replacement preserves the previous readable article.
  Successful replacement removes the prior versioned content directory. Additive
  schema migration retains legacy records and content paths.
- Render local HTML with embedded local images, block network access, disable file
  access/storage, sanitize content and apply a restrictive CSP. Page-authored scripts
  cannot execute; native-injected selection/highlight scripts are separate.
- Retain reading offset, select text to highlight, locate/delete highlights, edit or
  remove notes, remove topic assignments, filter archive/failure/tag/topic, and search
  body, title, source, notes, tags and topics.
- Export portable HTML or Markdown with embedded image data; cancellation is not a
  failure, while export errors produce user feedback. Deleting an article removes
  its content, images and article-scoped annotations after confirmation.

## Intentional limits

Extraction cannot guarantee success for login walls, challenges, removed articles or
content that has not loaded. Users must open the source, complete legitimate access,
then retry. There is no bypass of site authentication or anti-abuse controls.

Images use unauthenticated requests, at most 30 files, 5 MiB per file and 20 MiB total.
A 15-second budget stops scheduling further image requests; individual network
timeouts can extend an in-flight request beyond that scheduling deadline. Missing or
denied images are counted and the result is partial, not reported as fully offline.

Repeated identical text selections currently use the existing quote/context anchor
creation behavior; selecting a later identical occurrence can need relocation. A
precise DOM-range anchor is follow-up work, not a claimed acceptance result.

## Verification

Executed on the working checkout (which also contains preserved, unrelated changes):

- `hvigorw test`: 170 passed, 0 failures/errors/ignored. The actual result was read
  from `entry/.test/default/intermediates/test/coverage_data/test_result.txt`.
- `hvigorw assembleHap`: signed HAP built successfully through the canonical signing
  source guard. This is local build evidence, not CI publication or store delivery.
- Production reader scripts in headless Chrome: 7/7 passed, including WeChat long
  content, non-article rejection, deterministic extraction and reader enter/exit.
- `ARTICLE_TEST_BROWSER=chrome npm run test:articles` in `tools/reader-mode`: 12/12
  passed. Tests execute production ETS using explicit platform adapters and real
  browser DOMs, covering JSON decoding, lazy images, sanitization/CSP, selection and
  cross-inline highlighting, image failures, export embedding, delayed/stalled
  capture, disk/database failure preservation, scoped deletion and concurrent saves.

The Node harness uses the installed Harmony SDK TypeScript compiler; set
`ARTICLE_TEST_TYPESCRIPT` if its location differs. RDB/file failure tests use adapters,
so they do not replace real-device persistence or migration acceptance.

A separate index-only snapshot at `/tmp/zhuo-article-staged.eqpgac` excludes the
unrelated onboarding, settings and IAP edits. Its signed `hvigorw assembleHap` build
and all 12 article tests also passed. This verifies the task-owned commit does not
depend on the concurrent UI changes. The HAP SHA-256 is
`0c819248dcab8759c566e9f8178f1c6ef8f57a32a3dec8ee84c66502d5d9b005`.
An additional `hvigorw test` in that temporary snapshot compiled successfully but
stalled in `GenerateUnitTestResult` without producing a result file; it was
interrupted and is **not counted as a passing run**. The 170-test result above belongs
to the original working checkout.

An earlier candidate HAP installed on the connected device. Initial launch was
blocked by screen lock (10106102). A later launch command returned success, but the
foreground inspection showed another app; testing was stopped to avoid interfering
with concurrent device use. **No article-library device interaction is marked passed.**
The supplied live WeChat page was not available as a URL, and frozen fixture success
does not prove that exact page now saves successfully.

See `tool/agent_harmony_tests/article-library/report.html` for the outstanding device
matrix. No production promotion, AGC upload/submission, or push was performed.

## Harmony code review

Reviewed task-owned changes across style, typed models, state ownership, rendering,
navigation and exception handling. Capture/storage/export live in services/repository;
the existing Index overlay orchestrates UI callbacks. User messages use resources.

- P0: no known unresolved issue found in the reviewed changes.
- P1: real-device acceptance is still required before release; the matrix explicitly
  includes compact/landscape keyboard layouts, entitlement boundaries and persistence.
- P2: the existing Index and library sheet remain large; extract the article feature
  coordinator and list-row component in a follow-up. Large-library search still
  performs linear scans and per-article topic lookups; benchmark before claiming
  large-collection performance. Precise repeated-quote anchoring remains follow-up.
- Conclusion: source/build checks pass; release acceptance is **not complete**.

## Release acceptance

Before promoting this feature, obtain the original failing WeChat URL and an exclusive
unlocked device session. Verify all three entry points, actual toast/list outcomes,
offline relaunch with images, retry preserving notes, export through the system picker,
selection/highlight restoration, deletion, legacy library migration, and expired-Pro
read/export behavior. Synchronize the Cyclar issue once write access is available.
