# ZhuoBrowser release rules

- The private runner file `~/.config/zhuobrowser/signing.json` is the only
  editable signing source. Each channel has exactly one profile/certificate
  selection. Project build profiles are generated, never independent authorities.
- Use `scripts/mobile_cicd/signing-source.mjs` to select, validate, snapshot,
  or replace signing inputs. Direct DevEco/Hvigor builds must pass the same
  canonical-source check. Never silently fall back to cached `.ohos` profiles.
- Specified-device delivery is part of the accepted CI workflow. A successful
  AppGallery artifact upload alone does not complete portal delivery.
- Build only the accepted CI source SHA. Bind the device release to its signing
  input digest and allocated monotonic build number. Profile-only changes must
  produce a new immutable release, not overwrite source-SHA-only objects.
- Before publishing, verify the HAP signature, exact embedded profile,
  certificate, IAP capability, official manifest signature, full live checksums,
  HEAD lengths, and byte ranges. Recheck canonical input drift before promotion.
- Only the product-scoped portal API may promote a normal release. Do not
  directly update shared D1 release pointers or give CI a portal admin/recovery
  credential. Recovery requires an explicit target, expected current release,
  reason, and audit record; rollback pauses automatic promotion.
- A failed/skipped test, build, signing check, upload, or publication gate must
  leave the previous install pointer intact. Do not report uploaded as published,
  or published as device/IAP acceptance.
- Keep AGC upload, association, submission, review and publication manual.
- Preserve pre-existing worktree changes. Commit only task-owned changes on
  `main`; do not push, amend, or rewrite history without explicit authorization.

See `docs/harmony-signing-pipeline.md` for setup, verification and recovery.
