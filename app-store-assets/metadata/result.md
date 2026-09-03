# AGC Metadata Delivery Result

Status: saved and verified for the selected scope on 2026-09-03.

App: Zhuoyue Browser, com.youdroid.zhuobrowser. AGC app ID: 6917614109541548410. Draft: v2020673007369873856. Locale: Simplified Chinese.

## Saved and verified

- App information: website and support email.
- Version information: full description (786 characters), tagline (11 characters), review notes (144 characters), membership charging, no generative AI, and custom privacy policy URL.
- Five V2 phone screenshots at 1080 x 1920, in the order Home / Opening choices / Reader controls / Site blocking / Reader mode. These replace the original three images. All were loaded after a fresh navigation and visually matched the prepared assets. Existing values and checked states in 71 inputs were preserved; generated DOM IDs changed on reload and were excluded from comparison.
- AGC displayed separate successful-save dialogs for version and app information. Verification followed a full page reload and navigation back into the version draft.

The support email is visibly correct after reload; the browser DOM accessor returned an empty value, so its verification uses the screenshot rather than treating that accessor as authoritative.

## Deferred or not applicable

- The user-agreement URL appears in the saved description. Custom privacy mode offers no separate user-agreement URL input; no hosted agreement was created.
- Tablet and PC/2in1 screenshots, release binary association, age rating, privacy labels, filing/copyright and verified review contacts remain incomplete. The app has not been submitted or published.
- Existing Browser (primary) / Tools tags were preserved. They appeared after the form fully loaded, resolving the earlier uncertainty in the review.
- ASC was not selected because no iOS project or verified ASC record was available.
- Cyclar issue tracking is blocked by missing connector authentication and a signed-out web session. Restore Cyclar access to attach this delivery result to an issue.

## Screenshot revision V2

The user selected AGC in the native store picker after reviewing all five images. The refreshed images use neutral local placeholder pages, with actual app controls and actual blocking counters. AGC displayed “保存成功。”; the save button was disabled after reload. No submission or publication was performed.

- [V2 review](screenshot-revision-v2/review.md)
- [V2 readback](screenshot-revision-v2/readback.json)
- [V2 remote image ordering](screenshot-revision-v2/agc-readback.png)

## Initial delivery evidence (historical)

- [Selection record](selection.json)
- [App field readback](evidence/agc-app-readback.json)
- [Version field and image readback](evidence/agc-version-readback.json)
- [Visible support email](evidence/agc-support-email.png)
- [Remote screenshot ordering](evidence/agc-phone-images.png)

[Open AGC draft](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/myApp/6917614109541548410/v2020673007369873856)
