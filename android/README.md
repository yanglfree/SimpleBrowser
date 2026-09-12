# Zhuoyue Browser for Android

Kotlin + Jetpack Compose + system `WebView`. HarmonyOS remains the product
source of truth in `../ohos`. Shared scripts and network rules live in `../core`.

Phone V1 on this shell: native `browser://home`, tabs (including private),
address bar, EasyList network blocking on a background `shouldInterceptRequest`,
search-engine settings, a per-site allow-list, bookmarks, history, omni
suggestions, system share, reader mode (shared extraction core), find-in-page,
and a desktop user-agent toggle, and attachment downloads into the app-private
Downloads folder. Private tabs skip session restore and never
write history or bookmarks; cookie isolation uses AndroidX WebView profiles
when the WebView provider supports them.

Do not rewrite the HarmonyOS client in Flutter.

## Setup

```bash
cd ../core && npm run export-js && npm run export-rules
cd ../android
./Scripts/sync-core.sh
./gradlew :app:assembleDebug
```

`ANDROID_HOME` or `android/local.properties` must point at an Android SDK with
platform 35.

## Blocking

`shouldInterceptRequest` matches precompiled `{host,path}` rules from
`core/rules/android-network.json`. It does not run EasyList on the UI thread.
Allow-listed page hosts skip blocking for that tab, matching Harmony `rawHost`.

## Library

Bookmarks, history, and address-bar suggestions follow `core/src/library-policy.mjs`.
Private tabs never record visits or persist session. Share uses
`Intent.ACTION_SEND`. Reader mode injects `reader-extraction-core.js`; find uses
the system `WebView` find APIs; desktop UA matches `core` `DESKTOP_USER_AGENT`
and rewrites `m.weibo.cn`. `WebView` `DownloadListener` saves attachments into
app-private storage and lists them for share via `FileProvider`. Site
permissions are not in this shell yet.
