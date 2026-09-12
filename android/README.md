# Zhuoyue Browser for Android

Kotlin + Jetpack Compose + system `WebView`. HarmonyOS remains the product
source of truth in `../ohos`. Shared scripts and network rules live in `../core`.

Phone V1 on this shell: native `browser://home`, tabs (including private),
address bar, EasyList network blocking on a background `shouldInterceptRequest`,
search-engine settings, and a per-site allow-list. Private tabs skip session
restore; cookie isolation uses AndroidX WebView profiles when the WebView
provider supports them, otherwise history is still not recorded.

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
