#!/usr/bin/env bash

set -euo pipefail

FILE=""
SOURCE_SHA=""
VERSION=""
BUILD=""
UPLOAD_URL=""
UPLOAD_TOKEN=""

die() { echo "Artifact upload error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --source-sha) SOURCE_SHA="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --upload-url) UPLOAD_URL="${2:-}"; shift 2 ;;
    --upload-token) UPLOAD_TOKEN="${2:-}"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -f "${FILE}" ]] || die "artifact file not found"
[[ "${SOURCE_SHA}" =~ ^[a-f0-9]{40}$ ]] || die "source SHA must contain 40 lowercase hexadecimal characters"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must use semantic x.y.z form"
[[ "${BUILD}" =~ ^[1-9][0-9]*$ ]] || die "build must be a positive integer"
[[ "${UPLOAD_URL}" == https://*/api/artifacts && -n "${UPLOAD_TOKEN}" ]] || die "upload URL and token are required"

NAME="$(basename "${FILE}")"
CHECKSUM="$(shasum -a 256 "${FILE}" | awk '{print $1}')"
case "${NAME}" in
  *.json) CONTENT_TYPE="application/json" ;;
  SHA256SUMS) CONTENT_TYPE="text/plain; charset=utf-8" ;;
  *.hap) CONTENT_TYPE="application/octet-stream" ;;
  *) CONTENT_TYPE="application/octet-stream" ;;
esac

curl --fail-with-body --silent --show-error \
  --request PUT \
  --retry 2 \
  --retry-all-errors \
  --connect-timeout 15 \
  --max-time 900 \
  --header "Authorization: Bearer ${UPLOAD_TOKEN}" \
  --header "Content-Type: ${CONTENT_TYPE}" \
  --header "X-Artifact-SHA256: ${CHECKSUM}" \
  --header "X-Artifact-Version: ${VERSION}" \
  --header "X-Artifact-Build: ${BUILD}" \
  --data-binary "@${FILE}" \
  "${UPLOAD_URL}/${SOURCE_SHA}/${NAME}"

echo
echo "MOBILE_ARTIFACT_UPLOAD_OK name=${NAME} sha256=${CHECKSUM}"
