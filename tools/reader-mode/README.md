# Reader mode quality gate

This harness executes the exact production extraction core against frozen DOM fixtures.
Every reported extraction failure must add a fixture with beginning, middle, and ending
anchors before the algorithm changes.

## Deterministic release gate

```bash
cd tools/reader-mode
npm ci
npm test
```

The gate requires all positive fixtures to meet their text, structure, image, and anchor
expectations; non-article fixtures must remain unavailable. Fixtures never execute page
scripts or contact external hosts.

## Live canary

```bash
cd tools/reader-mode
npm run test:live
```

Live canaries detect publisher DOM drift. They are diagnostic rather than deterministic:
network, anti-bot, authentication, and publisher failures are reported separately from
extraction quality and must not replace the frozen release gate.

## HarmonyOS device fixture

```bash
cd tools/reader-mode
./device-fixture.sh [optional-hdc-target]
```

The script starts the local server and creates an HDC reverse port. Open the printed URL in
ZhuoBrowser, enter reader mode, verify all three anchors, change font/line-height/paper,
scroll to the end, then exit and confirm the original page is restored. This is interaction
acceptance; `hvigorw assembleHap` and the desktop browser harness do not replace it.

## Release targets

- Core supported publishers: 100% of frozen fixtures.
- Overall positive corpus: at least 95% complete.
- Required beginning/middle/end anchors: 100%.
- Non-article false-positive rate: at most 2%.
- Previously reported failures: 100% regression pass.
- Any output below 70% of its golden reference is release-blocking.

Telemetry may contain only the host, extraction strategy, result, coarse size/ratio/paragraph
buckets, image count, and duration. It must never include URL paths, titles, article text,
selected text, form values, or image URLs.
