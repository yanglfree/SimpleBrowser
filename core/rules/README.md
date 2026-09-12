Generated Safari `WKContentRuleList` JSON compiled from
`ohos/entry/src/main/resources/rawfile/ads`.

Do not edit these files. After changing a filter list:

```bash
cd core
npm run export-rules
```

CI runs `npm run export-rules:check`. Each list is capped at 50,000 rules,
the historical per-list WebKit limit. Supplement and EasyList China are
compiled in full; EasyList is truncated after network blocks fill the cap.
