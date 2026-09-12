# Harmony review follow-up — BRO-111

The source fixes are implemented; reviewer-device acceptance is still open.

## Changes

- A single root-owned system-bar style drives both the visible backdrop and native icon colors. Modal changes, settings updates, browser state and layout-class changes use the same refresh method. Stale asynchronous window requests are ignored; unchanged styles and already-fullscreen layouts skip native updates.
- A 60% black scrim covers the wallpaper status area and fades below it. Even a white wallpaper remains above 3:1 contrast with white status content. Light/dark pages and reader sheets use the actual surface background and matching content color.
- Privacy consent is persisted before dismissing the dialog or starting consent-dependent services. Settings writes now propagate failures, restore the Preferences cache on a failed flush, and publish repository/view-model state only after successful persistence. The save queue remains usable after failure.
- Privacy card height now uses the current window height. Its top/bottom clearance includes the live system insets. Avoid-area listeners update system and navigation insets on window changes and are removed when the page leaves.
- The existing immediate home-switch update remains. Home wallpaper decoding no longer uses synchronous image loading; delayed consent startup work is canceled when the page leaves.
- The launcher has one 1024x1024 AppScope PNG. Duplicate entry resources were removed; the original vector artwork is preserved in `app-store-assets/app-icon-source.svg`.
- Build number increased to 1000024 because the connected device rejected replacing installed build 1000023 with source build 1000018, including a downgrade attempt. No uninstall or data reset was performed.
- Browser Node regression tests are now a CI gate.

## Review

| Dimension | Result |
| --- | --- |
| Types and ArkTS compatibility | Native HAP build passed; thrown errors use ArkTS-compatible Error objects. |
| State ownership | Root owns system chrome; persisted settings are published after successful writes. |
| Rendering | Backdrop is non-interactive; no network work in its builder; synchronous wallpaper load removed. |
| Lifecycle | Pending startup timer and avoid-area listener cleaned up; stale native style requests ignored. |
| Error handling | Persistence failures reach the UI; cache rollback and retry are covered by production-method tests. |
| Resources | Single launcher icon source; settings failure text uses the existing Chinese resource catalog. |

No additional source blocker was found in the changed paths. Do not treat this review as physical-device or AppGallery approval.

## Verification

- `node --test scripts/*.test.mjs`: 40 passed, 0 failed.
- `hvigorw assembleHap`: successful.
- Canonical signing selection, native HAP signature, embedded profile/certificate and debug IAP capability: verified.
- `actionlint -color`, CI cost contract and `git diff --check`: passed.
- Root and entry-target Hvigor tests compiled but did not produce fresh results. Old result files dated September 6/9 were excluded. Only processes started for these attempts were stopped; pre-existing Previewer processes were preserved.
- A 1000024 candidate installed with retained data and visibly rendered the existing webpage. Further taps stopped after the phone foreground switched to WeChat; exclusive device time was requested. The last fullscreen-call optimization was built after that pause and has no final UI acceptance claim.

## Remaining acceptance

1. On the final candidate, verify wallpaper, no wallpaper, light/dark appearance, reader papers, modal open/close and settings changes. Measure status contrast and verify the native content color does not flip unexpectedly.
2. Measure the actual privacy buttons and compact Dock against the bottom navigation region; test portrait, landscape and constrained/foldable windows.
3. Verify both home switches and input in settings search, custom search, quick-site editor, article import/search/annotations, feedback and webpage forms. Include mouse/keyboard on a MateBook-class device.
4. Repeat the reviewer's click-completion scenario with a performance trace. Removing synchronous work is not proof that the reported 2683ms case passes.
5. Submit the separately produced AGC candidate manually when ready. No portal release, AGC upload, association, submission or publication occurred in this task.

## Icon interpretation

A processed 512px icon inside a HAP is not sufficient evidence of a bad source resource: Huawei documents that the IDE may resize a desktop icon while building. The previous review's size concern was narrowed to the verified duplicate-resource conflict; that conflict is fixed. Final store checking remains separate.

Reference: [Huawei desktop icon resource processing FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1149).

`cases.json` records the validation/QA boundary. `evidence/artifact.json` identifies the final local HAP; `report.html` is generated from the manifest.
