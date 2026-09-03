#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${1:-}"
SIGNING_TARGET="${REPO_ROOT}/build-profile.json5"
SIGNING_CHANNEL="${HARMONY_CHANNEL:-app_gallery}"
HVIGOR_BIN="${HVIGOR_BIN:-hvigorw}"
HAP_SIGN_TOOL="${HAP_SIGN_TOOL:-${HOME}/Library/Huawei/CommandLineTools/current/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar}"
BACKUP_DIR="$(mktemp -d)"

die() { echo "Harmony artifact build error: $*" >&2; exit 1; }

[[ -n "${OUTPUT_DIR}" ]] || die "an output directory is required"
[[ "${SIGNING_CHANNEL}" == app_gallery || "${SIGNING_CHANNEL}" == internaltesting ]] || die "unsupported distribution channel"
[[ -f "${HAP_SIGN_TOOL}" ]] || die "HAP signature verifier is missing"
command -v "${HVIGOR_BIN}" >/dev/null 2>&1 || [[ -x "${HVIGOR_BIN}" ]] || die "hvigorw is unavailable"
command -v ohpm >/dev/null 2>&1 || die "ohpm is unavailable"

restore_profile() {
  if [[ -f "${BACKUP_DIR}/app.json5" ]]; then
    cp "${BACKUP_DIR}/app.json5" "${REPO_ROOT}/AppScope/app.json5"
  fi
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
INPUT_DIGEST="$(node "${REPO_ROOT}/scripts/mobile_cicd/signing-source.mjs" fingerprint "${SIGNING_CHANNEL}")"
node "${REPO_ROOT}/scripts/mobile_cicd/signing-source.mjs" snapshot "${SIGNING_CHANNEL}" "${BACKUP_DIR}/signing"
SIGNING_SOURCE="${BACKUP_DIR}/signing/build-profile.json5"
cp "${SIGNING_SOURCE}" "${SIGNING_TARGET}"
if [[ -n "${HARMONY_BUILD_NUMBER:-}" ]]; then
  [[ "${SIGNING_CHANNEL}" == internaltesting ]] || die "build allocation is only for device releases"
  cp "${REPO_ROOT}/AppScope/app.json5" "${BACKUP_DIR}/app.json5"
  APP_SCOPE="${REPO_ROOT}/AppScope/app.json5" node <<'NODE'
const fs = require('node:fs');
const build = Number(process.env.HARMONY_BUILD_NUMBER);
if (!Number.isSafeInteger(build) || build < 1 || build >= 2147483647) throw new Error('Invalid build allocation');
const path = process.env.APP_SCOPE;
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
data.app.versionCode = build;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
NODE
fi

(
  cd "${REPO_ROOT}"
  ohpm install --all
)
(
  cd "${REPO_ROOT}/entry"
  ohpm install
)

(
  cd "${REPO_ROOT}"
  if [[ "${RUN_HARMONY_TESTS:-0}" == "1" ]]; then
    "${HVIGOR_BIN}" test
  fi
  "${HVIGOR_BIN}" assembleHap -p buildMode=release
)

HAP_PATH="${REPO_ROOT}/entry/build/default/outputs/default/entry-default-signed.hap"
[[ -f "${HAP_PATH}" ]] || die "signed HAP was not produced"
unzip -tq "${HAP_PATH}" >/dev/null
java -jar "${HAP_SIGN_TOOL}" verify-app -inFile "${HAP_PATH}" \
  -outCertChain "${BACKUP_DIR}/hap-chain.cer" -outProfile "${BACKUP_DIR}/hap-profile.p7b" \
  > "${BACKUP_DIR}/signature-verification.log" 2>&1 || die "HAP signature verification failed"
SIGNING_METADATA="$(node "${REPO_ROOT}/scripts/mobile_cicd/verify_harmony_signing.mjs" \
  "${SIGNING_SOURCE}" "${SIGNING_CHANNEL}" "${BACKUP_DIR}/hap-profile.p7b" "${BACKUP_DIR}/hap-chain.cer")" || die "HAP profile verification failed"
[[ "${INPUT_DIGEST}" == "$(node "${REPO_ROOT}/scripts/mobile_cicd/signing-source.mjs" fingerprint "${SIGNING_CHANNEL}")" ]] || die "signing source changed during build"

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
    ARTIFACT_NAME="${ARTIFACT_NAME}" SIGNING_METADATA="${SIGNING_METADATA}" INPUT_DIGEST="${INPUT_DIGEST}" node <<'NODE' > release-metadata.json
const payload = {
  app: process.env.APP_NAME,
  platform: "harmony",
  artifact: process.env.ARTIFACT_NAME,
  bundleName: process.env.BUNDLE_NAME,
  versionName: process.env.VERSION_NAME,
  versionCode: Number(process.env.VERSION_CODE),
  sourceSha: process.env.SOURCE_SHA,
  signing: JSON.parse(process.env.SIGNING_METADATA),
  inputDigest: process.env.INPUT_DIGEST,
};
process.stdout.write(`${JSON.stringify(payload)}\n`);
NODE
)

echo "HARMONY_ARTIFACTS_READY version=${VERSION_NAME}+${VERSION_CODE} output=${DESTINATION}"
