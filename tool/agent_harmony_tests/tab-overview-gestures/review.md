# Harmony Code Review

## Overview

- ArkTS files reviewed: 2 (task-owned hunks only).
- P0: 0. P1: 0. P2: 1 (extended gesture/device coverage remains not-run).
- Conclusion: passed for the targeted click-routing repair.

## Root cause and scope

The uncommitted background-dismiss implementation applied `HitTestMode.Block`
to each card. That prevents its close-button descendant from participating in
hit testing. Real device clicks on the close icon selected the card instead;
the count stayed at four. Two identical home titles represented distinct tab
IDs, not duplicated rendering of one ID.

Retain default descendant hit testing and register background dismissal only
once on the overview root. Existing close/select/new actions retain their
child-first click priority. Keep the existing by-reference builders, horizontal
pan and long-press recognizers. Do not introduce automatic home-tab deduplication
or change session/last-tab semantics.

Reference: [OpenHarmony hit-test control](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-hit-test-behavior.md).

## Six-dimension review

| Dimension | Result |
| --- | --- |
| Style | Existing naming, indentation and callback conventions retained. |
| Types | Existing typed onDismiss callback; no casts or new platform APIs. |
| State | No new state, mutation flags, coordinate caches or redundant models. |
| Rendering | No new rendering-time computation; preserve scroll fill and grid builders. |
| Routing | Only the Tabs overlay dismissal binding is staged in Index. |
| Logging and exceptions | No new production logs, secrets or exception paths. |

## Verification boundaries

Signed local build, overwrite installation, launch and 170 unit tests passed.
Six focused real-device cases passed; see cases.json. Device close smoke asserts
exact surviving card identities and removal of the underlying tab view, not
merely disappearance of the overview. Diagnostic screenshots/layouts live in
the ignored output/tab-overview-gesture-fix directory.

The first compile rejected an attempted ClickEvent.stopPropagation call; that
approach was removed. The final implementation uses native default click
priority and has no unsupported API calls.

Other dirty files are user-owned and excluded from the commit. Tests/builds used
the current worktree, not a clean CI snapshot. Bulk close, private long press,
horizontal swipe, long-list scrolling and last-tab close were not exercised.
No push, portal promotion or store operation was performed.
