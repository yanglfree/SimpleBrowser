#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/.." && pwd)"

CHANNEL="all"
SKIP_NOTARIZE=false
DRY_RUN=false
VERSION="1.0.0"
NOTARY_PROFILE="${ZHUO_NOTARY_PROFILE:-}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-Developer ID Application: Michale Yang (Y4MB2B6UD3)}"
MAS_SIGN_IDENTITY="${MAS_SIGN_IDENTITY:-}"
TEAM_ID="${DEVELOPMENT_TEAM:-Y4MB2B6UD3}"

usage() {
  cat <<'EOF'
Usage: build-release-packages.sh [options]

Build ZhuoBrowser Mac dual-channel release packages:
  1) Mac App Store (MAS) build with ZHUO_DISTRIBUTION_CHANNEL=appstore
  2) Official Website Developer ID signed & notarized Universal DMG with ZHUO_DISTRIBUTION_CHANNEL=dmg

Options:
  --channel <mas|dmg|all>   Target channel to build (default: all)
  --skip-notarize           Skip xcrun notarytool submission for DMG
  --notary-profile <name>   Keychain profile name for xcrun notarytool
  --version <semver>        Version string for DMG filename (default: 1.0.0)
  --dry-run                 Validate tools, config, and print commands only
  -h, --help                Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      [[ $# -ge 2 ]] || { echo "Missing value for --channel" >&2; exit 1; }
      CHANNEL="$2"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=true
      shift
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --notary-profile" >&2; exit 1; }
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      VERSION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$CHANNEL" in
  mas|dmg|all) ;;
  *)
    echo "Invalid --channel: $CHANNEL (expected mas, dmg, or all)" >&2
    exit 1
    ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command '$1' not found in PATH." >&2
    exit 1
  }
}

require_cmd xcodegen
require_cmd xcodebuild
require_cmd codesign
require_cmd hdiutil
require_cmd xcrun
require_cmd shasum

echo "==> Repo root: $REPO_ROOT"
echo "==> Channel:   $CHANNEL  Version: $VERSION  Dry-run: $DRY_RUN"

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Verified tools: xcodegen, xcodebuild, codesign, hdiutil, xcrun, shasum."
  echo "[dry-run] Would run: $SCRIPT_DIR/sync-core.sh && (cd $MACOS_DIR && xcodegen generate)"
  if [[ "$CHANNEL" == "mas" || "$CHANNEL" == "all" ]]; then
    echo "[dry-run] Would build MAS Universal Release -> $MACOS_DIR/.build/Release-MAS/ZhuoBrowserMac.app (ZHUO_DISTRIBUTION_CHANNEL=appstore)"
  fi
  if [[ "$CHANNEL" == "dmg" || "$CHANNEL" == "all" ]]; then
    echo "[dry-run] Would build & sign Universal DMG -> $REPO_ROOT/web/downloads/ZhuoBrowser-${VERSION}-mac-universal.dmg (ZHUO_DISTRIBUTION_CHANNEL=dmg)"
  fi
  exit 0
fi

"$SCRIPT_DIR/sync-core.sh"
(
  cd "$MACOS_DIR"
  xcodegen generate
)

build_mas() {
  local mas_out_dir="$MACOS_DIR/.build/Release-MAS"
  local mas_derived="$MACOS_DIR/.build/DerivedData-MAS"
  local mas_app="$mas_out_dir/ZhuoBrowserMac.app"
  rm -rf "$mas_out_dir"
  mkdir -p "$mas_out_dir"

  local sign_flags=()
  if [[ -n "$MAS_SIGN_IDENTITY" ]]; then
    sign_flags+=(CODE_SIGN_IDENTITY="$MAS_SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID")
  else
    sign_flags+=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic)
  fi

  echo "==> Building Mac App Store Universal Release (ZHUO_DISTRIBUTION_CHANNEL=appstore)..."
  xcodebuild \
    -project "$MACOS_DIR/ZhuoBrowserMac.xcodeproj" \
    -scheme ZhuoBrowserMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$mas_derived" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$mas_out_dir" \
    ZHUO_DISTRIBUTION_CHANNEL=appstore \
    "${sign_flags[@]}" \
    build

  [[ -d "$mas_app" ]] || { echo "Error: MAS build output missing at $mas_app" >&2; exit 1; }

  local actual_channel
  actual_channel="$(/usr/libexec/PlistBuddy -c "Print :ZhuoDistributionChannel" "$mas_app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$actual_channel" != "appstore" ]]; then
    echo "Error: expected ZhuoDistributionChannel=appstore, got '$actual_channel'" >&2
    exit 1
  fi

  echo "==> Verifying MAS App Sandbox entitlements..."
  codesign -d --entitlements :- "$mas_app" 2>/dev/null | grep -q "com.apple.security.app-sandbox" || {
    echo "Error: MAS binary is missing com.apple.security.app-sandbox entitlement." >&2
    exit 1
  }

  echo "==> MAS Release app ready: $mas_app (ZhuoDistributionChannel=$actual_channel)"
  echo "    To archive and upload to App Store Connect:"
  echo "    xcodebuild -project \"$MACOS_DIR/ZhuoBrowserMac.xcodeproj\" -scheme ZhuoBrowserMac -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO ZHUO_DISTRIBUTION_CHANNEL=appstore -archivePath \"$MACOS_DIR/.build/ZhuoBrowserMac-MAS.xcarchive\" archive"
}

build_dmg() {
  local dmg_out_dir="$MACOS_DIR/.build/Release-DMG"
  local dmg_derived="$MACOS_DIR/.build/DerivedData-DMG"
  local dmg_staging="$MACOS_DIR/.build/DMG-Staging"
  local dmg_app="$dmg_out_dir/ZhuoBrowserMac.app"
  local downloads_dir="$REPO_ROOT/web/downloads"
  local dmg_path="$downloads_dir/ZhuoBrowser-${VERSION}-mac-universal.dmg"

  rm -rf "$dmg_out_dir" "$dmg_staging"
  mkdir -p "$dmg_out_dir" "$dmg_staging" "$downloads_dir"

  echo "==> Building Direct DMG Universal Release (ZHUO_DISTRIBUTION_CHANNEL=dmg)..."
  xcodebuild \
    -project "$MACOS_DIR/ZhuoBrowserMac.xcodeproj" \
    -scheme ZhuoBrowserMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$dmg_derived" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$dmg_out_dir" \
    ZHUO_DISTRIBUTION_CHANNEL=dmg \
    ENABLE_HARDENED_RUNTIME=YES \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DMG_SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

  [[ -d "$dmg_app" ]] || { echo "Error: DMG app output missing at $dmg_app" >&2; exit 1; }

  local actual_channel
  actual_channel="$(/usr/libexec/PlistBuddy -c "Print :ZhuoDistributionChannel" "$dmg_app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$actual_channel" != "dmg" ]]; then
    echo "Error: expected ZhuoDistributionChannel=dmg, got '$actual_channel'" >&2
    exit 1
  fi

  echo "==> Verifying Developer ID signature on app bundle..."
  codesign --verify --deep --strict --verbose=2 "$dmg_app"

  echo "==> Creating Universal DMG at $dmg_path..."
  ditto "$dmg_app" "$dmg_staging/Zhuo浏览器.app"
  ln -s /Applications "$dmg_staging/Applications"
  rm -f "$dmg_path"

  hdiutil create \
    -volname "Zhuo浏览器 ${VERSION}" \
    -srcfolder "$dmg_staging" \
    -ov \
    -format UDZO \
    "$dmg_path"

  echo "==> Signing DMG with $DMG_SIGN_IDENTITY..."
  codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$dmg_path"

  if [[ "$SKIP_NOTARIZE" == false ]]; then
    if [[ -n "$NOTARY_PROFILE" ]]; then
      echo "==> Submitting DMG for Apple notarization (profile: $NOTARY_PROFILE)..."
      xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$dmg_path"
      xcrun stapler validate "$dmg_path"
    elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
      echo "==> Submitting DMG for Apple notarization (Apple ID: $APPLE_ID)..."
      xcrun notarytool submit "$dmg_path" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
      xcrun stapler staple "$dmg_path"
      xcrun stapler validate "$dmg_path"
    else
      echo "Note: Skipping automatic notarization (no --notary-profile or APPLE_ID/APPLE_APP_PASSWORD set)."
      echo "Run manually when ready:"
      echo "  xcrun notarytool submit \"$dmg_path\" --keychain-profile <profile> --wait"
      echo "  xcrun stapler staple \"$dmg_path\" && xcrun stapler validate \"$dmg_path\""
    fi
  fi

  local sha256
  sha256="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
  local size_bytes
  size_bytes="$(stat -f%z "$dmg_path")"
  echo "==> DMG ready: $dmg_path"
  echo "    Size:   $size_bytes bytes"
  echo "    SHA256: $sha256"
}

if [[ "$CHANNEL" == "mas" || "$CHANNEL" == "all" ]]; then
  build_mas
fi

if [[ "$CHANNEL" == "dmg" || "$CHANNEL" == "all" ]]; then
  build_dmg
fi
