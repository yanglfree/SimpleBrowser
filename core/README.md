# zhuobrowser-core

Portable assets and contracts for Zhuoyue Browser on HarmonyOS, iOS, and Android.

HarmonyOS stays on ArkTS/ArkWeb in this repository. This package does **not**
replace that client. It extracts the pieces other platforms can share:

- Injected JavaScript (reader, cosmetic cleanup, document-start guards)
- EasyList-style → `WKContentRuleList` compilation
- URL / session / kernel policy with golden tests
- Design tokens and the `BrowserKernel` method table

## Source of truth

Injected scripts still live in `ohos/entry/src/main/ets/constants/AppConstants.ets`.
`src/injected-scripts.mjs` parses that file the same way `tools/reader-mode`
already does. `core/js/` is a generated snapshot for native bundling.

```bash
cd core
npm test
npm run export-js:check
```

Do not edit `core/js/` by hand. Change `AppConstants.ets`, then run
`npm run export-js`.

## Layout

```
src/     extractors, rule compiler, portable policy
js/      generated script snapshot (committed)
spec/    kernel table, TypeScript models, Phone V1 matrix
tokens/  light/dark color tokens from DESIGN.md
test/    Node tests
```

The iOS shell is `ios/`. Copy `js/` into that app bundle with
`ios/Scripts/sync-core.sh`. Chrome is native against `spec/kernel.md`; do not
share UI widgets.
