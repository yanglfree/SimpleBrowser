# AGC Release Readiness

Prepared for ZhuoBrowser 1.0.1. Product behavior is implemented through `b100501b97cf5ed5a54a0b23246a89b1a8f00512`; the full release report and tablet acceptance evidence are recorded through `607f881728ddcf1596e0c04454859d717fa3db2c`. The final AppGallery package must be built from the later `main` commit that contains this readiness update.

This file separates answers supported by the current binary from declarations or materials that still require an AGC console decision. It is preparation evidence only; it does not mean that a package has been associated, uploaded, submitted, reviewed, or published.

## Privacy data flow

| Data or capability | Stored on device | Sent to ZhuoBrowser service | Sent to another party | Purpose and trigger | AGC declaration guidance |
| --- | --- | --- | --- | --- | --- |
| Browsing history, tabs, bookmarks, quick sites, settings and site exceptions | Yes | No | Page requests go to the website or search provider chosen by the user | Core browser behavior | Do not declare as developer-collected data. Explain local storage and user-controlled deletion. |
| Cookies, web storage and cache | Yes, managed by ArkWeb | No | Exchanged with the visited website as required by the website | Website session and page loading | Do not declare as developer-collected data. Disclose that websites apply their own policies. |
| Offline article source URL, title, author, excerpt, extracted HTML/Markdown, images, topics, notes, highlights and reading position | Yes | No | Only when the user explicitly exports or shares a file | Pro local reading library | Do not declare as developer-collected data. Explain local storage, explicit sharing and item deletion. |
| Optional reliability events | Yes, in the HarmonyOS HiAppEvent directory | No | No processor or network uploader is registered by the app | User must enable the setting; private tabs suppress every event | Do not declare as developer-collected diagnostics. The payload omits URLs, hosts, page text, search terms and free-form exception messages. |
| Random installation identifier | Yes | Yes, `gateway.youdroid.top` | No | Entitlement lookup, verification, restore and duplicate-delivery prevention | Declare a device or other identifier used for app functionality and fraud prevention. It is pseudonymous and is not an AppGallery account identifier. |
| AppGallery purchase evidence | Pending purchase state may be stored until completion | Yes, `gateway.youdroid.top` | AppGallery processes the payment | Product ID/type, order ID, purchase token, raw purchase data, idempotency key, platform/app ID, client event time and reason are sent for verification or restore | Declare purchase information used for app functionality and fraud prevention. The app does not receive bank-card or payment-password data. |
| Camera and microphone | No app-owned recording | No | Granted to the requesting website only after a site request and user decision | WebRTC or web capture initiated by the visited website | Keep the sensitive-permission usage reasons. State that ZhuoBrowser does not retain or upload captured media. |
| Precise or approximate location | Site decision is stored locally | No | Granted to the requesting website only after a site request and user decision | Website geolocation initiated by the visited website | Keep the sensitive-permission usage reason. State that ZhuoBrowser does not retain or upload location coordinates. |
| Download-directory files | Yes, in the user-authorized download directory | No | Only when the user shares a file | Download, export and file sharing | Keep the download-directory permission reason. Do not declare file contents as developer-collected data. |
| Clipboard text | Read only through the explicit Visit Clipboard Link action | No | The resulting address is sent to the selected website when the user visits it | User-initiated navigation | State the explicit trigger if AGC asks about clipboard access. |

Supported deletion behavior:

- Settings can clear history, cookies, web storage, cache, site permissions and exceptions by the selected time range.
- Bookmarks and offline articles can be deleted individually.
- Uninstalling removes app-private data. Files the user exported or downloaded into shared storage remain under user control.
- Purchase and entitlement records remain on the verification service for the period required to deliver purchases, restore entitlements, process refunds and meet legal obligations.

## Sensitive permission explanations

| Permission | Console explanation |
| --- | --- |
| Camera | A visited website can request camera access. ZhuoBrowser asks the user before granting the request and does not retain or upload captured media. |
| Microphone | A visited website can request microphone access. ZhuoBrowser asks the user before granting the request and does not retain or upload audio. |
| Precise and approximate location | A visited website can request location access. ZhuoBrowser asks the user before granting the request and does not retain or upload the returned coordinates. |
| Read/write download directory | Used only when the user downloads a file or exports browser content to the authorized public download directory. |

The release profile and `entry/src/main/module.json5` must contain the same permissions. If AGC classifies any of these as restricted, attach the required usage-reason video rather than omitting the permission from the declaration.

## Age rating questionnaire notes

- The app is not designed only for children: use `childFlag = 0` if the API field is used.
- The app itself does not publish violence, sexual content, gambling, drugs or profanity, and it does not host a social feed or user-generated-content service.
- The app provides user-directed access to the open web. If the questionnaire asks whether unrestricted Internet or third-party content can be accessed, answer yes.
- The app offers AppGallery in-app purchases and auto-renewable subscriptions. Answer yes when a question asks about digital purchases or subscriptions.
- Websites may provide communication, user-generated content or location features. Answer based on the exact questionnaire wording and treat open-web access as present rather than claiming that all third-party content is controlled by ZhuoBrowser.
- Do not choose a numeric rating before the completed questionnaire returns AGC's calculated result.

## Release materials and console gates

| Gate | Current state | Required action |
| --- | --- | --- |
| Public privacy policy | Published and verified | Keep `https://browser.youdroid.top/privacy.html` in the AGC draft. The 2026-09-04 deployment serves the a7bc961 wording through Worker version `2cddc25e-cff1-4d55-95a8-d9713f4ac1f5`. |
| Phone screenshots | Ready and already read back from the draft | Keep the five current 1080 x 1920 images in the verified order. |
| Tablet screenshots | Ready locally, not saved in AGC | Four real-device promotional images without a purchase screen are available in Chinese and English at 2730 x 1820 (3:2). Upload only the locale set enabled in the draft, then read back their order. |
| PC/2in1 screenshots | Missing | `entry/src/main/module.json5` still declares `2in1`. Complete real-device acceptance and capture assets, or remove that device type through the product requirement workflow before submission. |
| Privacy labels | Prepared, not saved | Enter the declarations from the matrix and read them back from AGC. |
| Age rating | Questionnaire not completed | Complete it using the notes above and retain the calculated result. |
| Software copyright or equivalent authorization | Missing from the repository | Provide the mainland-China copyright or agent-authorization material required by AGC. Do not fabricate or substitute screenshots. |
| Filing material | App shows `鄂ICP备2024064800号-14A`; supporting console material is not verified | Confirm the corresponding filing record and upload any AGC-requested proof. |
| Review contact | Not verified | Confirm the real reviewer contact and complete any phone verification code in AGC. Do not store personal phone data in this repository. |
| AppGallery package | Final package not pinned yet | Build and validate the exact final `main` commit, then associate and upload that `.app` only after all release QA gates pass and immediately after explicit external-mutation confirmation. |
| Submission | Not started | Submit only after package association, declarations, materials and final review-page readback all pass. |

## Current release evidence

- Full release matrix: 112 cases, 101 passed, 7 partial, 4 blocked and 0 failed as recorded in `tool/agent_harmony_tests/full-release/`.
- CI source `d93b8729b2cf79aa485b4d09d3e20a4a4bc34207`: tests and HarmonyOS build passed in run `33889596080`.
- Specified-device release source `d93b8729b2cf79aa485b4d09d3e20a4a4bc34207`: signed artifact retention and verified portal publication passed in run `33889790708`.
- Published specified-device build: 1.0.1 (1000007), release ID `72c8ed4b10f8dc922a5a49e0c6f2ab13c081fbc7514071083327e4873e55b245`, HAP SHA-256 `af0fa68b31b046d10cd7721b1dd524f9f3de6ca2399128e628dfe95be221cc46`.
- Tablet data restore: all five article-library database files were read back byte-for-byte after restoration; the cold-launched library showed zero articles, matching the snapshot contents.
- Tablet assets: `app-store-assets/generated/harmony-agc-tablet/{zh-Hans,en}/`, four 2730 x 1820 (3:2) PNG files per locale, all below 5 MB. The purchase screen is intentionally excluded.
- Phone dated fixtures: expired-tab archive/keep/relaunch/restore and seven-day history retention passed on source `2f80eafecacdb1be0b6e842a49be310cb80ace8a`; the history sheet now refreshes immediately after pruning, and all 35 original data files matched their snapshot digests after restoration.

These facts do not make the release submission-ready while partial and blocked cases remain. The final AppGallery `.app` path and SHA-256 are intentionally pinned after this document is committed so the package source is immutable and exact.
