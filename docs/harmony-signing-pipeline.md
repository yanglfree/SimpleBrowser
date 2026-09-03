# Canonical Harmony signing and device publication

## Authorities

There are two different authorities, not a Profile file on the portal:

1. The runner's mode-600 `~/.config/zhuobrowser/signing.json` owns signing inputs.
   It contains `schemaVersion: 1`, `signingConfigs` with `default`, `dis`, and
   `device` identities, the private `portalBase`, and `manifestSignTool` path.
   Each profile remains at its original path. Credentials never enter Git.
2. The portal's `specified-device` release pointer owns installation state.
   It can reference only a verified immutable release. The portal never signs
   HAPs or reads files from the maintainer Mac.

`config/harmony-build-profile.json` owns non-secret SDK/module configuration.
`signing-source.mjs` derives the project signing configuration and freezes the
profile/certificate bytes for each build. Hvigor rejects selections that differ
from the canonical source. The keystore remains at its canonical location so
Huawei's encrypted-password material can be resolved; actual HAP signing-key
compatibility is checked after signing.

The previous `build-profile.release.json5` and `build-profile.device.json5`
runner files are legacy compatibility inputs for workflows predating this
change. New workflows do not read them. Archive them after the new workflows
are activated; do not retire them while older accepted jobs are still running.

## Triggers and ordering

```text
push main / manual CI / scheduled device-profile fingerprint check
  -> CI accepts an exact source SHA
  -> store artifacts retained with run/attempt-qualified immutable filenames
  -> product-scoped portal API reserves a new device release/build number
  -> device HAP + official signed manifest + icon + verification metadata
  -> upload -> full GET/hash + HEAD/length + Range verification
  -> recheck signing-source fingerprint
  -> atomic compare-and-swap publication -> live stable-manifest verification
```

The scheduled gate runs twice an hour on the existing self-hosted runner. It
compares source SHA and the device signing-input digest to the portal's live
record. Unchanged inputs skip compilation; invalid/expired inputs fail visibly.
GitHub schedules can be delayed and require an online runner. This is bounded
eventual refresh, not an instantaneous filesystem watcher.

For an immediate Profile refresh, use:

```bash
node scripts/mobile_cicd/signing-source.mjs replace-profile internaltesting /absolute/new-device.p7b
```

The command validates against the enrolled app/certificate, atomically replaces
the canonical Profile, and dispatches CI. If dispatch fails, it exits with an
error; the local replacement remains and the scheduled device check can recover.
For certificate/key rotation, update the one private source as an operator and
dispatch CI after validating all affected channels. The scheduled check is for
the device-install channel; debug/store-only changes use this explicit dispatch
or the next source push.

Use `sync-local debug` for local development and `snapshot <channel> <directory>`
for diagnostic signing. Never infer installation success from either command.

## Publication trust boundary

The shared portal enrolls each product and bundle name in
`harmony_product_policies`. Upload credentials are stored as SHA-256 digests and
derive product identity server-side. CI receives only `harmony:publish`.
The trusted runner performs native HAP and official manifest cryptographic
verification; the Worker does not pretend to execute Huawei's Java verifier.
The Worker validates the resulting authenticated attestation, retained object
hashes/lengths, manifest links, app identity, profile/certificate metadata, and
complete artifact set before changing a pointer.

Device release IDs include product, source SHA, signing-input digest and accepted
CI run ID. A D1 allocator produces increasing build numbers, including when code
does not change. Public `/harmony/builds/<release-id>/<artifact>` routes identify
exact objects. Staged objects are available at those unlisted URLs for live
verification, but never become the install action before publication.

Publication uses a transactional expected-pointer check. A lower build number or
older accepted CI cannot replace a newer release. Content-addressed R2 keys and
immutable artifact rows reject a rebuild that produces different bytes under
the same release ID. For such a failed attempt, dispatch a new upstream CI run
(a new run ID), rather than retrying the same run; do not overwrite the old object.

The normal registry API refuses to overwrite an enrolled product's channel.
Cloudflare administrators still have break-glass database authority; rules are
not a substitute for controlling those credentials.

## Activation sequence

Source changes are not activated merely by a local commit. Before enabling:

1. Review and commit both ZhuoBrowser and `mobile-cicd-portal` changes.
2. With deployment authorization, export the portal D1 database to its ignored
   backup directory, apply additive migration `0004_harmony_pipeline.sql`, and
   deploy the verified portal Worker. Keep all legacy releases/URLs intact.
3. Enroll this existing product using the portal repository's operator helper:

   ```bash
   node scripts/enroll-harmony.mjs zhuobrowser com.youdroid.zhuobrowser yanglfree/SimpleBrowser --apply
   ```

   It requires existing operator Cloudflare/GitHub authorization, creates an
   isolated Keychain credential, and sets GitHub environment secret
   `PORTAL_UPLOAD_TOKEN` in `mobile-distribution`. It never prints the token.
4. After push authorization, push the commits. Verify upstream CI and the
   automatic receiver use the exact same SHA and CI run identity. The receiver
   must exist on the default branch before expecting `workflow_run` triggers.
5. Verify the live portal pointer, signed manifest and immutable HAP. Separately
   test overwrite-install compatibility and the IAP environment on the phone.

No AGC store operation is part of this sequence. No migration/deployment/push is
implicitly performed by a local build or by reading this document.

## Verification

```bash
node --test scripts/mobile_cicd/*.test.mjs
python3 scripts/mobile_cicd/check_ci_cost_contract.py
actionlint -color
bash -n scripts/mobile_cicd/build_harmony_artifacts.sh
node scripts/mobile_cicd/signing-source.mjs assert-selected
node scripts/mobile_cicd/release-device.mjs build-only /absolute/private/output
```

Run `pnpm verify` in the portal repository. Its pipeline tests use real SQLite
transactions and an in-memory object adapter to exercise authorization, stale
publication, incomplete/corrupt artifacts, profile drift, immutable conflicts,
live resource routing and audited rollback. Real builds additionally validate
the SDK signer and Huawei manifest tool; local tests do not prove Cloudflare or
physical-device delivery.

## Recovery

Keep prior immutable releases. A separate operator credential, created with
`enroll-harmony.mjs ... --recovery`, has `harmony:rollback` and stays out of CI.
Recovery calls `POST /api/v1/harmony/releases/<id>/rollback` with the expected
current release ID, explicit reason, `verified: true`, and independently checked
artifact hashes. Only a previously published, non-revoked, unexpired release is
eligible. Rollback creates an audit event and pauses auto-publication.

After resolving the fault, the recovery principal can call
`POST /api/v1/harmony/releases/<current-id>/resume` with `expectedCurrent` and a
reason. Resuming is audited. Then dispatch CI for the desired signing inputs.
An old package may not be installable as a downgrade; restoring a pointer is not
proof that a device can downgrade, and never implies permission to uninstall or
erase user data. Existing pre-pipeline releases remain retained for operator
recovery but cannot silently bypass the new verification contract.

Huawei reference: [Constructing a Deeplink to download an app](https://developer.huawei.com/consumer/cn/doc/app/agc-help-internal-test-release-app-0000002260691994),
updated 2026-06-25 08:59:34. The implementation uses the official manifest signing
tool, same-domain resources, HEAD sizes and Range responses required there.
