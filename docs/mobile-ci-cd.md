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
node --test scripts/mobile_cicd/verify_harmony_signing.test.mjs
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

## Signing refresh and browser-install channel

Local signing configuration is private and ignored by Git. The maintainer Mac
uses these separate selections, all referencing the original downloaded profile
paths rather than stale copies:

| Configuration | Selected signer | Profile | Purpose |
| --- | --- | --- | --- |
| Project `build-profile.json5` | `default` | `~/browser_debugDebug.p7b` | Local debugging |
| `~/.config/zhuobrowser/build-profile.release.json5` | `dis` | `~/browser_disRelease.p7b` | AppGallery artifact retention |
| `~/.config/zhuobrowser/build-profile.device.json5` | `device` | `~/browser_deviceRelease.p7b` | Specified-device signing |

The debug signer uses the existing `piano_debug.cer` / `piano.p12` identity;
the release and device signers use `all_dis.cer` / `all_dis.p12`. These names
identify shared developer certificates, not application identities. The profile
must still bind the ZhuoBrowser bundle and app identifier. Keep passwords and
private keys outside Git, and keep each configuration at mode `600`.

Validate a selection without exposing signing secrets:

```bash
node scripts/mobile_cicd/verify_harmony_signing.mjs build-profile.json5 debug
node scripts/mobile_cicd/verify_harmony_signing.mjs \
  "$HOME/.config/zhuobrowser/build-profile.release.json5" app_gallery
node scripts/mobile_cicd/verify_harmony_signing.mjs \
  "$HOME/.config/zhuobrowser/build-profile.device.json5" internaltesting
```

The artifact script requires an AppGallery profile, validates IAP capability,
identity, validity, and the matching certificate before building. After building,
it verifies the HAP signature, exact embedded profile bytes, and actual signing
certificate. Non-secret signing metadata is retained in `release-metadata.json`.
Do not point this store-retention job at the device profile: browser installation
also needs its own signed manifest and publication step.

### Confirmed state on 2026-09-03

- The browser-install portal is `downloads.youdroid.top`. Its ZhuoBrowser
  channel is a separately registered, managed specified-device release. The
  current GitHub workflows upload to the product Worker; they do not update
  the shared portal's specified-device manifest or channel pointer.
- The live portal still serves `1.0.1 / 1000001` at source
  `27ca023fe22eae08e4fd0e138080c40f40f318e2`, HAP SHA-256
  `23281cdd8f93493c487f8392ea2770d4c04380a4c60b83af0c16084d2f287379`.
  Its embedded profile UUID is `695ba71e-82b8-456e-a4d9-cc0a0c3330a1`,
  type `release / internaltesting`, without the IAP capability. Its actual
  signing certificate also differs from the certificate bound by its profile.
- CI run `33583321653` failed its 8 GiB disk preflight on September 2;
  downstream run `33583411258` was skipped. The latest successful artifact
  workflow was `33522880660` on September 1. Updating a `.p7b` file does not
  trigger GitHub Actions, rebuild immutable R2 objects, or update installed apps.
- The refreshed profiles contain IAP capability. The local debug, store and
  device configurations have been paired with their corresponding certificates.
  The debug profile expires on October 4, 2026 and needs timely renewal.

For the next authorized device release, build with the device configuration,
verify its embedded IAP profile and signing certificate, generate a matching
signed manifest, and publish under a new immutable release identity. Verify the
portal checksum and channel pointer before testing the phone. Do not overwrite
the old SHA-keyed package or uninstall an existing app without checking data and
signing compatibility. A successful local signing check does not prove IAP
availability on the phone or automatically republish this channel.
