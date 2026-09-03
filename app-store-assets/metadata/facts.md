# Zhuoyue Browser Store Facts

Prepared: 2026-09-03. Target: HarmonyOS 1.0.1, com.youdroid.zhuobrowser.

## Verified sources

- AppScope/app.json5: source version 1.0.1 (1000001); device package query also reports 1.0.1 (1000001).
- entry/src/main/module.json5: phone, tablet, 2in1; system link and share receiving.
- README.md and FEATURES.md: broad inventory, cross-checked against implementation; older scope statements are not authoritative when code differs.
- entry/src/main/ets/pages/Index.ets: external-open choices, reader controls, Pro gates around article library and saving.
- entry/src/main/ets/models/ProModels.ets: Pro article library, offline article, export, annotation, workbench; monthly/yearly/lifetime product types.
- entry/src/main/ets/services/ArticleExportService.ets: Markdown and standalone HTML exports.
- entry/src/main/ets/repositories/ArticleLibraryRepository.ets and services/ArticleSearchService.ets: local article storage and search.
- entry/src/main/ets/models/BrowserModels.ets: telemetry defaults off.
- website/privacy.html and website/terms.html: local-data and paid-feature boundaries; confirmed visible on the live public website in the authenticated browser. Generic HTTP clients returned 403; browser rendering succeeded.
- Live AGC draft: app 6917614109541548410; draft v2020673007369873856; Simplified Chinese only; no associated release binary; status Prepare for Submission.

## Positioning

A HarmonyOS browser for moving from everyday links to focused reading and a local collection of useful material. Free browsing, reader mode and blocking form the entry experience; Pro provides article storage, search, annotations, topics and export. Do not promise perfect ad removal, universal extraction, absolute anonymity, fully offline entitlement validation, cloud sync, AI assistance or measured speed gains.

## Screenshot evidence

Three fresh captures from the installed HarmonyOS 1.0.1 app: home, external-link opening choices, reader mode. The page shown is the product-owned privacy policy; no private third-party article was exported. Raw captures are preserved under app-store-assets/source/harmony-phone/zh-Hans. Device identity is omitted from public artifacts. The device switched to other applications during collection, so further device interactions were stopped. These screenshots prove the visible screens only, not full release QA.

## Scope limitations

The working tree contains concurrent product changes, including purchase recovery and privacy/onboarding work. They were preserved and are not part of this metadata delivery. No build was produced or associated. The proposed copy must be rechecked against the actual store binary before submission. Tablet and PC/2in1 remain declared platforms; no phone screenshot is represented as their UI.

ASC is not a filling target: no iOS source tree or ASC app identity was found. Cyclar MCP has no available credential; the web session requires login and no Chrome browser was available. An issue could not be created or updated in this run.
