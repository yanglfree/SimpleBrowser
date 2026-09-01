#!/usr/bin/env bash

set -euo pipefail

[[ $# -ge 3 && $# -le 4 ]] || {
  echo "Usage: $0 <download-url> <source-sha> <expected-status> [minimum-artifacts]" >&2
  exit 2
}

download_url="${1%/}"
source_sha="$2"
expected_status="$3"
minimum_artifacts="${4:-1}"
response="$(curl --fail --silent --show-error "${download_url}/builds/harmony/${source_sha}")"

STATUS_JSON="${response}" EXPECTED_STATUS="${expected_status}" MINIMUM_ARTIFACTS="${minimum_artifacts}" node <<'NODE'
const payload = JSON.parse(process.env.STATUS_JSON);
if (payload.status !== process.env.EXPECTED_STATUS) throw new Error(`unexpected build status: ${payload.status}`);
const artifacts = payload.artifacts ?? [];
const minimum = Number(process.env.MINIMUM_ARTIFACTS);
if (artifacts.length < minimum) throw new Error(`expected at least ${minimum} artifacts, found ${artifacts.length}`);
for (const artifact of artifacts) {
  if (!artifact.sha256 || !artifact.bytes || !artifact.object_key) throw new Error("artifact metadata is incomplete");
}
process.stdout.write(`${JSON.stringify(payload)}\n`);
NODE
