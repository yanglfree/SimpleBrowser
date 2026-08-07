# Dolphin Agent Harness

This project exposes Dolphin Browser as a deterministic, machine-readable HarmonyOS surface for AI agents. It drives a real device through `hdc` and `uitest`, locates production ArkUI controls semantically, and records evidence for every scenario step.

The harness is intentionally outside the application module. It neither adds debug UI to the HAP nor replaces the production components it evaluates.

## Contract

- Commands write one JSON document to standard output.
- Exit code `0` means the requested operation or scenario passed; exit code `1` means it failed.
- A scenario is validated before any device mutation.
- A locator must resolve to exactly one visible node unless an explicit `index` is provided.
- A matched non-clickable leaf is promoted to its nearest clickable ancestor.
- Device commands use argument arrays rather than shell interpolation.
- Every captured step stores a PNG screenshot and the raw ArkUI layout JSON.
- `launch.reset` is opt-in because it deletes the application's local data.

## Setup

Requirements are `uv`, HarmonyOS `hdc`, and one connected, unlocked device or simulator.

```bash
cd harness
uv sync
uv run dolphin-harness doctor
```

`doctor` wakes the display, verifies that exactly one requested device is connected, and fails with a structured error when the device is locked. The harness never attempts to bypass a device passcode.

## Build, install, and run

Build from the repository root with the project's canonical command:

```bash
hvigorw assembleHap
```

Then use the harness from this directory:

```bash
uv run dolphin-harness install ../entry/build/default/outputs/default/entry-default-signed.hap
uv run dolphin-harness run scenarios/browser-smoke.json
```

The smoke scenario launches `EntryAbility`, verifies the browser address control, opens the real address sheet, verifies its input, captures it, dismisses it, and verifies the browser surface again.

## Commands

```text
dolphin-harness doctor
dolphin-harness install HAP
dolphin-harness run SCENARIO [--artifacts PATH]
dolphin-harness snapshot [--bundle BUNDLE] [--output PATH]
dolphin-harness tap VALUE [--kind id|text|description|type]
```

Every command accepts `--serial` when multiple devices are connected and `--hdc` when the binary is not on `PATH`.

## Scenario protocol

Scenarios are immutable JSON documents. The supported actions are:

- `launch`: wake-check and launch an ability; optional `reset` clears application data.
- `tap` and `long_press`: resolve a semantic locator and act at its center.
- `input_text`: resolve a locator and send text through `uitest`.
- `swipe`: drive an explicit coordinate gesture with a bounded velocity.
- `key`: send `Back`, `Home`, or `Power`.
- `assert_visible`: require one semantic locator to resolve.
- `snapshot`: create named screenshot and layout artifacts.

Locators support `id`, `text`, `description`, and `type`, exact or substring matching, plus an optional zero-based `index` for intentionally repeated controls.

```json
{
  "name": "open-address",
  "bundle": "com.youdroid.dolphin",
  "ability": "EntryAbility",
  "steps": [
    { "action": "launch", "reset": false },
    {
      "action": "tap",
      "locator": { "kind": "id", "value": "browser-address" }
    },
    {
      "action": "assert_visible",
      "locator": { "kind": "id", "value": "address-input" }
    },
    { "action": "snapshot", "name": "address-sheet" }
  ]
}
```

## Evidence

Runs create a timestamped directory under `artifacts/` containing:

```text
artifacts/<timestamp>-<scenario>/
  00-launch.png
  00-launch.json
  01-lookup.json
  01-assert_visible.png
  01-assert_visible.json
  report.json
```

`report.json` records the device, overall status, timestamps, duration and evidence paths for each step, plus the typed failure message when execution stops. The artifact directory is ignored by Git.

## Verification

```bash
uv run pytest
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
```
