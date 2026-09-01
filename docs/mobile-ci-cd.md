# Mobile CI/CD

ZhuoBrowser uses GitHub Actions only for orchestration and status. A trusted
Apple Silicon self-hosted runner performs HarmonyOS tests, signing, and HAP
builds. Cloudflare R2 retains immutable artifacts, D1 records build and checksum
metadata, and a product-isolated Worker provides authenticated upload plus an
unlisted download/status surface.

```text
push main or manual CI
  -> CI on [self-hosted, macOS, ARM64, harmonyos, zhuobrowser]
  -> successful workflow_run.head_sha
  -> signed HAP + SHA256SUMS + release-metadata.json
  -> authenticated Worker upload
  -> immutable R2 objects and D1 status
  -> optional downloads.youdroid.top registration after live verification
```

## Boundaries

- The automatic receiver always checks out the successful CI
  `workflow_run.head_sha`; it never rebuilds a moving `main` tip.
- Failed or skipped CI cannot upload artifacts.
- GitHub-hosted compute, Actions cache, and Actions artifacts are not used.
- The runner-local release signing profile is stored at
  `~/.config/zhuobrowser/build-profile.release.json5` with mode `600` and is
  never committed.
- R2 object keys use `harmony/<source-sha>/<artifact-name>` and are immutable.
- The Worker verifies the uploaded byte count and SHA-256 before recording D1.
- The unified `downloads.youdroid.top` portal remains a separate presentation
  and proxy layer. Do not mark ZhuoBrowser available there before the exact HAP,
  checksum, Range response, and rollback path pass production verification.
- AppGallery Connect upload, release association, submission, review, and
  publication remain manual.

The repository currently has no iOS/Xcode target, so there is no iOS archive,
Ad Hoc installation, TestFlight, or App Store workflow in this migration.

## Required external state

GitHub environment `mobile-distribution`:

- Secret `DISTRIBUTION_UPLOAD_TOKEN`
- Variable `DISTRIBUTION_UPLOAD_URL` ending in `/api/artifacts`
- Variable `HARMONY_DOWNLOAD_URL` containing the unlisted Worker channel URL

Cloudflare:

- Worker `zhuobrowser-mobile-distribution`
- R2 bucket `zhuobrowser-mobile-artifacts`
- D1 database `zhuobrowser-mobile-releases`
- Worker secret `UPLOAD_TOKEN`

Runner:

- Name `liang-mac-zhuobrowser`
- Labels `self-hosted`, `macOS`, `ARM64`, `harmonyos`, `zhuobrowser`
- Huawei Command Line Tools exposed through
  `~/Library/Huawei/CommandLineTools/current`
- Root and `entry` dependencies are resolved independently so the local
  `iap_paywall_kit` module never depends on a stale runner checkout.
- At least 8 GiB free disk before a job starts

Production Cloudflare identifiers and the download slug belong in ignored
`cloudflare/mobile-distribution/wrangler.production.jsonc` or provider state.

## Verification

Before pushing:

```bash
python3 scripts/mobile_cicd/check_ci_cost_contract.py
actionlint -color
for script in scripts/mobile_cicd/*.sh; do bash -n "$script"; done
cd cloudflare/mobile-distribution
npm ci
npm run typecheck
npm test
npm run verify:worker
```

After an authorized push, verify the upstream CI and automatic Harmony workflow
use the same SHA. Then independently verify D1 status and every live artifact:

```bash
scripts/mobile_cicd/verify_build_status.sh \
  "$HARMONY_DOWNLOAD_URL" "$SOURCE_SHA" uploaded 3

curl --fail --head \
  "$HARMONY_DOWNLOAD_URL/artifacts/harmony/$SOURCE_SHA/$HAP_NAME"

curl --fail --header 'Range: bytes=0-0' \
  "$HARMONY_DOWNLOAD_URL/artifacts/harmony/$SOURCE_SHA/$HAP_NAME"
```

Server-side retention does not prove installation, launch, changed-path
interaction, AGC association, review, or store publication. Record those as
separate states.
