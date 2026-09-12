#!/usr/bin/env zsh

# Zhuoyue Browser — local device runner.
# Style follows MarkBuy/run_release.sh: zsh, fail-fast, dry-run. Harmony uses
# the canonical signing source; iOS and Android install the native shells.
# Multiple connected devices prompt for a numbered choice on a TTY.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OHOS_DIR="$SCRIPT_DIR/ohos"
IOS_DIR="$SCRIPT_DIR/ios"
ANDROID_DIR="$SCRIPT_DIR/android"

DEVICE_TYPE=""
DEVICE_ID=""
SHOW_SIMULATOR=false
DRY_RUN=false
SKIP_SYNC=false
BUILD_APP=true
LAUNCH_APP=true
HARMONY_BUILD_MODE="release"

fail() {
  print -u2 -- "Error: $1"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./run_release.sh [options] [ohos|harmony|ios|android]

Build, install, and launch Zhuoyue Browser on a connected device.

Options:
  -d, --device <id>  Use a specific device id (hdc / udid / adb serial).
  -s, --simulator    Include iOS simulators.
      --debug        Harmony: assembleHap debug. Android/iOS: Debug.
      --no-sync      Skip ios/android Scripts/sync-core.sh.
      --no-build     Install an existing artifact.
      --no-launch    Install only.
      --dry-run      Validate tools and the selected device only.
  -h, --help         Show this help message.

Environment overrides:
  HDC_BIN            HarmonyOS hdc executable.
  HVIGORW_BIN        hvigorw executable.
  ADB_BIN            adb executable.
  XCRUN_BIN          xcrun executable.
  XCODEBUILD_BIN     xcodebuild executable.
  DEVELOPMENT_TEAM   Apple team id for physical iOS installs.

Examples:
  ./run_release.sh                 # prompt when more than one device is connected
  ./run_release.sh ohos
  ./run_release.sh -d <hdc-id>
  ./run_release.sh ios -s
  ./run_release.sh android --dry-run
EOF
}

resolve_command() {
  local name="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      print -- "$candidate"
      return 0
    fi
  done
  if (( $+commands[$name] )); then
    command -v "$name"
    return 0
  fi
  return 1
}

resolve_hdc() {
  resolve_command hdc \
    "${HDC_BIN:-}" \
    "$HOME/Library/Huawei/CommandLineTools/current/sdk/default/openharmony/toolchains/hdc" \
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc" \
    "$HOME/Library/OpenHarmony/Sdk/15/toolchains/hdc" \
    "$HOME/Library/OpenHarmony/Sdk/13/toolchains/hdc"
}

resolve_hvigorw() {
  resolve_command hvigorw \
    "${HVIGORW_BIN:-}" \
    "${HVIGORW_HOME:-}/bin/hvigorw" \
    "${HVIGORW_HOME:-}/hvigorw" \
    "$HOME/Library/Huawei/CommandLineTools/current/hvigor/bin/hvigorw" \
    "$HOME/Library/Huawei/CommandLineTools/current/bin/hvigorw" \
    "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"
}

resolve_adb() {
  resolve_command adb \
    "${ADB_BIN:-}" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"
}

while (( $# > 0 )); do
  case "$1" in
    -d|--device)
      (( $# >= 2 )) || fail "Missing device id after $1."
      DEVICE_ID="$2"
      shift 2
      ;;
    -s|--simulator)
      SHOW_SIMULATOR=true
      shift
      ;;
    --debug)
      HARMONY_BUILD_MODE="debug"
      shift
      ;;
    --no-sync)
      SKIP_SYNC=true
      shift
      ;;
    --no-build)
      BUILD_APP=false
      shift
      ;;
    --no-launch)
      LAUNCH_APP=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    ohos|harmony)
      DEVICE_TYPE="ohos"
      shift
      ;;
    ios)
      DEVICE_TYPE="ios"
      shift
      ;;
    android)
      DEVICE_TYPE="android"
      shift
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

prepare_harmony_env() {
  local hdc_bin="$1"
  local sdk_root="${hdc_bin:h:h:h:h}"
  if [[ -d "$sdk_root" ]]; then
    export DEVECO_SDK_HOME="$sdk_root"
  fi
  unset OHOS_SDK_HOME HOS_SDK_HOME
  export PATH="${hdc_bin:h}:$PATH"

  local plugin_nm=""
  local candidate
  for candidate in \
      "${HVIGORW_HOME:-}/hvigor-ohos-plugin/node_modules" \
      "$HOME/Library/Huawei/CommandLineTools/current/hvigor/hvigor-ohos-plugin/node_modules" \
      "/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      plugin_nm="$candidate"
      break
    fi
  done
  if [[ -n "$plugin_nm" ]]; then
    export NODE_PATH="$plugin_nm${NODE_PATH:+:$NODE_PATH}"
  fi
}

scan_devices() {
  local include_simulator="$1"
  local platform_filter="${2:-}"
  local hdc_bin="" adb_bin="" xcrun_bin=""
  if [[ -z "$platform_filter" || "$platform_filter" == "ohos" ]]; then
    hdc_bin="$(resolve_hdc || true)"
  fi
  if [[ -z "$platform_filter" || "$platform_filter" == "android" ]]; then
    adb_bin="$(resolve_adb || true)"
  fi
  if [[ -z "$platform_filter" || "$platform_filter" == "ios" ]]; then
    xcrun_bin="${XCRUN_BIN:-xcrun}"
  fi

  python3 - "$include_simulator" "$hdc_bin" "$adb_bin" "$xcrun_bin" <<'PY'
import json
import subprocess
import sys

include_simulator = sys.argv[1] == "true"
hdc_bin = sys.argv[2]
adb_bin = sys.argv[3]
xcrun_bin = sys.argv[4]
candidates = []

def run(args, timeout):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None

if hdc_bin:
    listed = run([hdc_bin, "list", "targets", "-v"], 3)
    found = False
    if listed and listed.stdout:
        for line in listed.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("[Empty]"):
                continue
            parts = line.split()
            if len(parts) >= 3 and "Connected" in parts:
                found = True
                candidates.append(("ohos", parts[0], f"HarmonyOS ({parts[0]})", "Connected"))
    if not found:
        listed = run([hdc_bin, "list", "targets"], 3)
        if listed and listed.stdout:
            for line in listed.stdout.splitlines():
                line = line.strip()
                if not line or line.startswith("[Empty]"):
                    continue
                candidates.append(("ohos", line.split()[0], f"HarmonyOS ({line.split()[0]})", "hdc"))

if xcrun_bin:
    listed = run([xcrun_bin, "xcdevice", "list"], 8)
    if listed and listed.stdout.strip().startswith("["):
        try:
            devices = json.loads(listed.stdout)
        except json.JSONDecodeError:
            devices = []
        for dev in devices:
            platform = dev.get("platform", "")
            is_sim = bool(dev.get("simulator"))
            available = bool(dev.get("available"))
            dev_id = dev.get("identifier", "")
            name = dev.get("name", "iOS Device")
            model = dev.get("modelName") or dev.get("modelCode") or ""
            label = f"{name} ({model})" if model else name
            if platform == "com.apple.platform.iphoneos" and not is_sim and available and dev_id:
                candidates.append(("ios", dev_id, label, "Physical iOS"))
            elif platform == "com.apple.platform.iphonesimulator" and include_simulator and available and dev_id:
                candidates.append(("ios_simulator", dev_id, f"{name} (Simulator)", "iOS Simulator"))

if adb_bin:
    listed = run([adb_bin, "devices", "-l"], 3)
    if listed and listed.stdout:
        for line in listed.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("List of devices"):
                continue
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                detail = " ".join(parts[2:]) if len(parts) > 2 else "Android"
                candidates.append(("android", parts[0], f"Android ({parts[0]})", detail))

for platform, dev_id, name, detail in candidates:
    print(f"{platform}\t{dev_id}\t{name}\t{detail}")
PY
}

choose_device() {
  print -- "Scanning HarmonyOS / iOS / Android devices..."
  local raw
  raw="$(scan_devices "$SHOW_SIMULATOR" "$DEVICE_TYPE")"

  local -a filtered=()
  local plat id name detail
  while IFS=$'\t' read -r plat id name detail; do
    [[ -n "${plat:-}" ]] || continue
    if [[ -n "$DEVICE_TYPE" ]]; then
      if [[ "$DEVICE_TYPE" == "ios" ]]; then
        [[ "$plat" == "ios" || "$plat" == "ios_simulator" ]] || continue
      else
        [[ "$plat" == "$DEVICE_TYPE" ]] || continue
      fi
    fi
    filtered+=("${plat}"$'\t'"${id}"$'\t'"${name}"$'\t'"${detail}")
  done <<< "$raw"

  if [[ -n "$DEVICE_ID" ]]; then
    local entry
    for entry in "${filtered[@]}"; do
      IFS=$'\t' read -r plat id name detail <<< "$entry"
      if [[ "$id" == "$DEVICE_ID" || "$name" == *"$DEVICE_ID"* ]]; then
        DEVICE_TYPE="$plat"
        DEVICE_ID="$id"
        print -- "Using $name [$plat] $id"
        return 0
      fi
    done
    if [[ -z "$DEVICE_TYPE" ]]; then
      if [[ "$DEVICE_ID" == *:* || "$DEVICE_ID" == 127.0.0.1* ]]; then
        DEVICE_TYPE="ohos"
      elif [[ "$DEVICE_ID" == emulator-* ]]; then
        DEVICE_TYPE="android"
      elif [[ "$DEVICE_ID" =~ ^[0-9A-F-]{36}$ ]]; then
        DEVICE_TYPE="ios_simulator"
      else
        DEVICE_TYPE="ohos"
      fi
    fi
    print -- "Using specified device $DEVICE_ID (platform $DEVICE_TYPE)"
    return 0
  fi

  local count="${#filtered[@]}"
  if (( count == 0 )); then
    fail "No connected device found. Check USB debugging, or pass -d <id>. Use -s to include iOS simulators."
  fi
  if (( count == 1 )); then
    IFS=$'\t' read -r DEVICE_TYPE DEVICE_ID name detail <<< "${filtered[1]}"
    print -- "Using $name [$DEVICE_TYPE] $DEVICE_ID"
    return 0
  fi

  print -- "Multiple devices are connected. Choose one:"
  local i=1
  local entry
  for entry in "${filtered[@]}"; do
    IFS=$'\t' read -r plat id name detail <<< "$entry"
    print -- "[$i] $name ($plat) $id"
    i=$((i + 1))
  done

  if [[ ! -t 0 ]]; then
    fail "Stdin is not a TTY. Re-run with --device <id>."
  fi

  local choice
  printf 'Select 1-%d (or q to quit): ' "$count"
  read -r choice
  [[ "$choice" == [qQ] ]] && exit 0
  [[ "$choice" =~ ^[0-9]+$ ]] || fail "Invalid selection: $choice"
  (( choice >= 1 && choice <= count )) || fail "Invalid selection: $choice"
  IFS=$'\t' read -r DEVICE_TYPE DEVICE_ID name detail <<< "${filtered[choice]}"
  print -- "Using $name [$DEVICE_TYPE] $DEVICE_ID"
}

sync_core() {
  local platform="$1"
  [[ "$SKIP_SYNC" == true ]] && return 0
  case "$platform" in
    ios|ios_simulator)
      [[ -x "$IOS_DIR/Scripts/sync-core.sh" ]] || fail "Missing $IOS_DIR/Scripts/sync-core.sh"
      "$IOS_DIR/Scripts/sync-core.sh"
      ;;
    android)
      [[ -x "$ANDROID_DIR/Scripts/sync-core.sh" ]] || fail "Missing $ANDROID_DIR/Scripts/sync-core.sh"
      "$ANDROID_DIR/Scripts/sync-core.sh"
      ;;
  esac
}

run_harmony() {
  local hdc_bin hvigorw_bin
  hdc_bin="$(resolve_hdc || true)"
  hvigorw_bin="$(resolve_hvigorw || true)"
  [[ -n "$hdc_bin" ]] || fail "HDC was not found. Set HDC_BIN to DevEco toolchains/hdc."
  [[ -n "$hvigorw_bin" ]] || fail "hvigorw was not found. Set HVIGORW_BIN or install DevEco / CommandLineTools."
  [[ -d "$OHOS_DIR" ]] || fail "HarmonyOS project not found: $OHOS_DIR"
  prepare_harmony_env "$hdc_bin"

  local bundle_name="com.youdroid.browser"
  local ability_name="EntryAbility"
  local parsed
  parsed="$(sed -nE 's/.*"bundleName"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$OHOS_DIR/AppScope/app.json5" | head -n 1 || true)"
  [[ -n "$parsed" ]] && bundle_name="$parsed"
  parsed="$(sed -nE 's/.*"mainElement"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$OHOS_DIR/entry/src/main/module.json5" | head -n 1 || true)"
  [[ -n "$parsed" ]] && ability_name="$parsed"

  print -- "Using hvigorw: $hvigorw_bin"
  print -- "Using HDC: $hdc_bin"
  print -- "HarmonyOS device: $DEVICE_ID"
  print -- "Bundle: $bundle_name  Ability: $ability_name  Mode: $HARMONY_BUILD_MODE"

  if [[ "$DRY_RUN" == true ]]; then
    print -- "Environment validation completed."
    return 0
  fi

  if [[ "$BUILD_APP" == true ]]; then
    print -- "Syncing local debug signing from the canonical source..."
    node "$SCRIPT_DIR/scripts/mobile_cicd/signing-source.mjs" sync-local debug
    print -- "Building HAP (assembleHap -p buildMode=$HARMONY_BUILD_MODE)..."
    (
      cd "$OHOS_DIR"
      "$hvigorw_bin" assembleHap -p "buildMode=$HARMONY_BUILD_MODE"
    )
  fi

  local hap_dir="$OHOS_DIR/entry/build/default/outputs/default"
  local hap_file
  hap_file="$(find "$hap_dir" -maxdepth 1 -type f -name '*-signed.hap' | head -n 1 || true)"
  [[ -n "$hap_file" && -f "$hap_file" ]] || fail "Signed HAP not found in $hap_dir. Check signing and the build log."

  print -- "Installing $hap_file ..."
  "$hdc_bin" -t "$DEVICE_ID" install -r "$hap_file"
  if [[ "$LAUNCH_APP" == true ]]; then
    print -- "Launching $bundle_name ..."
    "$hdc_bin" -t "$DEVICE_ID" shell aa force-stop "$bundle_name" >/dev/null 2>&1 || true
    if ! "$hdc_bin" -t "$DEVICE_ID" shell aa start -a "$ability_name" -b "$bundle_name"; then
      print -- "Installed, but launch failed. Unlock the device and open the icon."
    fi
  fi
  print -- "Done."
}

run_ios() {
  local xcrun_bin="${XCRUN_BIN:-xcrun}"
  local xcodebuild_bin="${XCODEBUILD_BIN:-xcodebuild}"
  (( $+commands[xcodegen] )) || fail "xcodegen was not found. Install it before running the iOS shell."
  [[ -d "$IOS_DIR" ]] || fail "iOS project not found: $IOS_DIR"

  local is_sim=false
  [[ "$DEVICE_TYPE" == "ios_simulator" ]] && is_sim=true
  local configuration="Release"
  [[ "$HARMONY_BUILD_MODE" == "debug" ]] && configuration="Debug"
  [[ "$is_sim" == true ]] && configuration="Debug"

  print -- "iOS device: $DEVICE_ID  Simulator: $is_sim  Configuration: $configuration"
  if [[ "$DRY_RUN" == true ]]; then
    print -- "Environment validation completed."
    return 0
  fi

  sync_core ios
  (
    cd "$IOS_DIR"
    xcodegen generate
  )

  local derived="$IOS_DIR/.build/DerivedData"
  local destination="id=$DEVICE_ID"
  local extra_flags=()
  if [[ "$is_sim" == true ]]; then
    extra_flags+=(CODE_SIGNING_ALLOWED=NO)
  elif [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    extra_flags+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi

  if [[ "$BUILD_APP" == true ]]; then
    print -- "Building iOS $configuration ..."
    "$xcodebuild_bin" \
      -project "$IOS_DIR/ZhuoBrowser.xcodeproj" \
      -scheme ZhuoBrowser \
      -configuration "$configuration" \
      -destination "$destination" \
      -derivedDataPath "$derived" \
      "${extra_flags[@]}" \
      build
  fi

  if [[ "$is_sim" == true ]]; then
    local app_bundle="$derived/Build/Products/${configuration}-iphonesimulator/ZhuoBrowser.app"
    [[ -d "$app_bundle" ]] || fail "Simulator app not found: $app_bundle"
    "$xcrun_bin" simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
    "$xcrun_bin" simctl install "$DEVICE_ID" "$app_bundle"
    if [[ "$LAUNCH_APP" == true ]]; then
      "$xcrun_bin" simctl launch "$DEVICE_ID" com.youdroid.zhuobrowser
    fi
  else
    local app_bundle="$derived/Build/Products/${configuration}-iphoneos/ZhuoBrowser.app"
    [[ -d "$app_bundle" ]] || fail "Device app not found: $app_bundle. Set DEVELOPMENT_TEAM or open ios/ in Xcode."
    "$xcrun_bin" devicectl device install app --device "$DEVICE_ID" "$app_bundle"
    if [[ "$LAUNCH_APP" == true ]]; then
      "$xcrun_bin" devicectl device process launch --device "$DEVICE_ID" com.youdroid.zhuobrowser
    fi
  fi
  print -- "Done."
}

run_android() {
  local adb_bin
  adb_bin="$(resolve_adb || true)"
  [[ -n "$adb_bin" ]] || fail "adb was not found. Set ADB_BIN or ANDROID_HOME."
  [[ -x "$ANDROID_DIR/gradlew" ]] || fail "Android Gradle wrapper not found: $ANDROID_DIR/gradlew"

  local apk="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
  print -- "Using adb: $adb_bin"
  print -- "Android device: $DEVICE_ID"
  if [[ "$DRY_RUN" == true ]]; then
    print -- "Environment validation completed."
    return 0
  fi

  sync_core android
  if [[ "$BUILD_APP" == true ]]; then
    print -- "Building debug APK ..."
    (
      cd "$ANDROID_DIR"
      ./gradlew :app:assembleDebug
    )
  fi
  [[ -f "$apk" ]] || fail "APK not found: $apk"
  print -- "Installing $apk ..."
  "$adb_bin" -s "$DEVICE_ID" install -r "$apk"
  if [[ "$LAUNCH_APP" == true ]]; then
    "$adb_bin" -s "$DEVICE_ID" shell am start -n com.youdroid.zhuobrowser/.MainActivity
  fi
  print -- "Done."
}

(( $+commands[python3] )) || fail "python3 is required to scan devices."

choose_device

case "$DEVICE_TYPE" in
  ohos|harmony) run_harmony ;;
  ios|ios_simulator) run_ios ;;
  android) run_android ;;
  *) fail "Unknown platform: $DEVICE_TYPE" ;;
esac
