#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
FORBIDDEN = (
    "ubuntu-latest",
    "macos-latest",
    "windows-latest",
    "actions/upload-artifact",
    "actions/download-artifact",
    "actions/cache",
)
REQUIRED = {
    "ci.yml": "name: CI",
    "harmony-artifacts.yml": "name: HarmonyOS Signed Artifacts",
}


def fail(message: str) -> None:
    raise SystemExit(f"CI cost contract failed: {message}")


workflow_files = sorted((*WORKFLOWS.glob("*.yml"), *WORKFLOWS.glob("*.yaml")))
if not workflow_files:
    fail("no workflows found")

for workflow in workflow_files:
    source = workflow.read_text(encoding="utf-8")
    lowered = source.lower()
    for signal in FORBIDDEN:
        if signal in lowered:
            fail(f"{workflow.name} contains forbidden hosted billing signal {signal}")
    for runs_on in re.findall(r"runs-on:\s*\[([^\]]+)]", source):
        labels = {value.strip().strip("'\"") for value in runs_on.split(",")}
        if not {"self-hosted", "macOS", "ARM64", "harmonyos", "zhuobrowser"}.issubset(labels):
            fail(f"{workflow.name} has an incomplete self-hosted label set: {sorted(labels)}")

for filename, expected_name in REQUIRED.items():
    path = WORKFLOWS / filename
    if not path.is_file() or expected_name not in path.read_text(encoding="utf-8"):
        fail(f"{filename} is missing or has the wrong workflow name")

release = (WORKFLOWS / "harmony-artifacts.yml").read_text(encoding="utf-8")
for fragment in (
    "workflow_run:",
    "workflow_dispatch:",
    "github.event.workflow_run.head_sha",
    "github.event.workflow_run.conclusion == 'success'",
    "ref: ${{ env.SOURCE_SHA }}",
):
    if fragment not in release:
        fail(f"harmony-artifacts.yml is missing accepted-source invariant: {fragment}")

all_workflows = "\n".join(path.read_text(encoding="utf-8").lower() for path in workflow_files)
for store_action in ("upload_to_app_gallery", "submit_for_review", "agc upload", "appgallery upload"):
    if store_action in all_workflows:
        fail(f"automated store action is forbidden: {store_action}")

print(f"CI_COST_CONTRACT_OK workflows={len(workflow_files)}")
