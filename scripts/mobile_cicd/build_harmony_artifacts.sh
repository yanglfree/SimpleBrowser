#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${1:-}"
SIGNING_SOURCE="${HARMONY_SIGNING_PROFILE:-${HOME}/.config/zhuobrowser/build-profile.release.json5}"
SIGNING_TARGET="${REPO_ROOT}/build-profile.json5"
HVIGOR_BIN="${HVIGOR_BIN:-hvigorw}"
BACKUP_DIR="$(mktemp -d)"

die() { echo "Harmony artifact build error: $*" >&2; exit 1; }

[[ -n "${OUTPUT_DIR}" ]] || die "an output directory is required"
[[ -f "${SIGNING_SOURCE}" ]] || die "runner-local signing profile is missing"
[[ "$(stat -f '%OLp' "${SIGNING_SOURCE}")" == "600" ]] || die "signing profile mode must be 600"
grep -Eq '"name"[[:space:]]*:[[:space:]]*"dis"' "${SIGNING_SOURCE}" || die "release signing config 'dis' is missing"
grep -Eq '"signingConfig"[[:space:]]*:[[:space:]]*"dis"' "${SIGNING_SOURCE}" || die "default product must use release signing config 'dis'"
command -v "${HVIGOR_BIN}" >/dev/null 2>&1 || [[ -x "${HVIGOR_BIN}" ]] || die "hvigorw is unavailable"

restore_profile() {
  if [[ -f "${BACKUP_DIR}/build-profile.json5" ]]; then
    cp "${BACKUP_DIR}/build-profile.json5" "${SIGNING_TARGET}"
  else
    rm -f "${SIGNING_TARGET}"
  fi
  rm -rf "${BACKUP_DIR}"
}
trap restore_profile EXIT INT TERM

if [[ -f "${SIGNING_TARGET}" ]]; then
  cp "${SIGNING_TARGET}" "${BACKUP_DIR}/build-profile.json5"
fi
cp "${SIGNING_SOURCE}" "${SIGNING_TARGET}"

(
  cd "${REPO_ROOT}"
  if [[ "${RUN_HARMONY_TESTS:-0}" == "1" ]]; then
    "${HVIGOR_BIN}" test
  fi
  "${HVIGOR_BIN}" assembleHap
)

HAP_PATH="$(find "${REPO_ROOT}/entry/build" -type f -name '*-signed.hap' -print | sort | tail -1)"
[[ -f "${HAP_PATH}" ]] || die "signed HAP was not produced"
unzip -tq "${HAP_PATH}" >/dev/null

PACKAGE_METADATA="$(HAP_PATH="${HAP_PATH}" node <<'NODE'
const { execFileSync } = require("node:child_process");
const archive = process.env.HAP_PATH;
const pack = JSON.parse(execFileSync("unzip", ["-p", archive, "pack.info"], { encoding: "utf8" }));
const moduleInfo = JSON.parse(execFileSync("unzip", ["-p", archive, "module.json"], { encoding: "utf8" }));
const app = pack.summary?.app;
if (!app || moduleInfo.app?.debug !== false || moduleInfo.app?.buildMode !== "release") process.exit(2);
process.stdout.write([app.bundleName, app.version?.name, app.version?.code].join("\t"));
NODE
)" || die "HAP package metadata is invalid"
IFS=$'\t' read -r BUNDLE_NAME VERSION_NAME VERSION_CODE <<< "${PACKAGE_METADATA}"

[[ "${BUNDLE_NAME}" == "com.youdroid.zhuobrowser" ]] || die "unexpected bundle name"
[[ "${VERSION_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version name"
[[ "${VERSION_CODE}" =~ ^[1-9][0-9]*$ ]] || die "invalid version code"

mkdir -p "${OUTPUT_DIR}"
DESTINATION="$(cd "${OUTPUT_DIR}" && pwd)"
ARTIFACT_NAME="ZhuoBrowser-HarmonyOS-${VERSION_NAME}+${VERSION_CODE}.hap"
cp "${HAP_PATH}" "${DESTINATION}/${ARTIFACT_NAME}"
(
  cd "${DESTINATION}"
  shasum -a 256 "${ARTIFACT_NAME}" > SHA256SUMS
  APP_NAME="zhuobrowser" BUNDLE_NAME="${BUNDLE_NAME}" VERSION_NAME="${VERSION_NAME}" \
    VERSION_CODE="${VERSION_CODE}" SOURCE_SHA="${SOURCE_SHA:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}" \
    ARTIFACT_NAME="${ARTIFACT_NAME}" node <<'NODE' > release-metadata.json
const payload = {
  app: process.env.APP_NAME,
  platform: "harmony",
  artifact: process.env.ARTIFACT_NAME,
  bundleName: process.env.BUNDLE_NAME,
  versionName: process.env.VERSION_NAME,
  versionCode: Number(process.env.VERSION_CODE),
  sourceSha: process.env.SOURCE_SHA,
};
process.stdout.write(`${JSON.stringify(payload)}\n`);
NODE
)

echo "HARMONY_ARTIFACTS_READY version=${VERSION_NAME}+${VERSION_CODE} output=${DESTINATION}"
