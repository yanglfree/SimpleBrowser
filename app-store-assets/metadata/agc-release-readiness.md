# AGC Release Readiness

Prepared for ZhuoBrowser 1.0.1 (1000001), source `a7bc9618c5768a5c17d3e5f1942b9994c82d790e`.

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
| Phone screenshots | Ready and already read back from the draft | Keep the five current 1080 x 1920 images in the verified order. |
| Tablet and PC/2in1 screenshots | Missing | Capture the current candidate on each declared form factor, or remove an unsupported device type before submission. |
| Privacy labels | Prepared, not saved | Enter the declarations from the matrix and read them back from AGC. |
| Age rating | Questionnaire not completed | Complete it using the notes above and retain the calculated result. |
| Software copyright or equivalent authorization | Missing from the repository | Provide the mainland-China copyright or agent-authorization material required by AGC. Do not fabricate or substitute screenshots. |
| Filing material | App shows `鄂ICP备2024064800号-14A`; supporting console material is not verified | Confirm the corresponding filing record and upload any AGC-requested proof. |
| Review contact | Not verified | Confirm the real reviewer contact and complete any phone verification code in AGC. Do not store personal phone data in this repository. |
| AppGallery package | Built and locally verified | Associate and upload the exact `.app` only after all release QA gates pass and immediately after explicit external-mutation confirmation. |
| Submission | Not started | Submit only after package association, declarations, materials and final review-page readback all pass. |

## Current pinned artifacts

- Debug device HAP: `output/full-device-qa-20260904/candidate-a7bc961/ZhuoBrowser-HarmonyOS-1.0.1+1000001-debug.hap`
- Debug HAP SHA-256: `c013cd05c8f1b9e15cbf8bd0163276102aa3da90f6b193862db86fbb26a7a6ba`
- AppGallery HAP SHA-256: `923e457af880d2916ae0da4065e966c70d8cbfd542779fadef197252d4b9735a`
- AppGallery APP: `output/agc-candidate-a7bc961/ZhuoBrowser-HarmonyOS-1.0.1+1000001.app`
- AppGallery APP SHA-256: `5f75d4b0d2738172199d959b7d67c2c913965e4a7c808903bbcf17a2de7f6629`
- Store profile UUID: `78e9a894-7a63-49c9-a302-880919ceebb6`

The artifacts under `output/` are ignored local evidence. Rebuild and re-pin them if product code changes.
