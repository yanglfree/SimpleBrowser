#!/usr/bin/env zsh

# Zhuoyue Browser — HarmonyOS release 构建与安装脚本。
# 用法: ./run_release.sh [-d device-id]
# 不带 -d 时会列出已连接设备并提示选择。

cd "$(dirname "$0")"

# 出错时立即退出
set -e

# Normalize the HarmonyOS command-line toolchain. DevEco Studio may have been
# removed while its environment variables remain in the parent shell.
COMMAND_LINE_TOOLS_ROOT="$HOME/Library/Huawei/CommandLineTools"
if [ ! -d "${DEVECO_HOME:-}" ] || [ ! -d "${DEVECO_SDK_HOME:-}" ]; then
    COMMAND_LINE_TOOLS_HOME=""
    for candidate in \
        "$COMMAND_LINE_TOOLS_ROOT/current" \
        $(find "$COMMAND_LINE_TOOLS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r); do
        if [ -d "$candidate/sdk" ] && [ -x "$candidate/tool/node/bin/node" ]; then
            COMMAND_LINE_TOOLS_HOME="$candidate"
            break
        fi
    done

    if [ -z "$COMMAND_LINE_TOOLS_HOME" ]; then
        echo "❌ 未找到 Huawei CommandLineTools，请安装并设置 DEVECO_HOME。"
        exit 1
    fi

    export DEVECO_HOME="$COMMAND_LINE_TOOLS_HOME"
    export DEVECO_TOOLS="$DEVECO_HOME"
    export DEVECO_NODE_HOME="$DEVECO_TOOLS/tool/node"
    export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
    export HVIGORW_HOME="$DEVECO_HOME/hvigor"
    export NODE_HOME="$DEVECO_NODE_HOME"
fi

# 定位工具链 -----------------------------------------------------------
# hvigorw：优先 HVIGORW_HOME / 项目自带 / CommandLineTools / DevEco Studio 内置
HVIGORW=""
for candidate in \
    "${HVIGORW_HOME:-}/bin/hvigorw" \
    "${HVIGORW_HOME:-}/hvigorw" \
    "$PWD/hvigorw" \
    "$HOME/Library/Huawei/CommandLineTools/current/bin/hvigorw" \
    "$HOME/Library/Huawei/CommandLineTools/current/hvigor/bin/hvigorw" \
    "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
    "$HOME/DevEcoStudio/tools/hvigor/bin/hvigorw"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        HVIGORW="$candidate"
        break
    fi
done
if [ -z "$HVIGORW" ]; then
    echo "❌ 未找到 hvigorw，请确认 DevEco Studio 已安装或设置 HVIGORW_HOME。"
    exit 1
fi

# hdc：优先系统 PATH，其次常见 SDK 路径
HDC=""
for candidate in \
    "$(command -v hdc 2>/dev/null)" \
    "${DEVECO_SDK_HOME:-}/default/openharmony/toolchains/hdc" \
    "$HOME/Library/Huawei/CommandLineTools/current/sdk/default/openharmony/toolchains/hdc" \
    "$HOME/Library/OpenHarmony/Sdk/15/toolchains/hdc" \
    "$HOME/Library/OpenHarmony/Sdk/13/toolchains/hdc" \
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        HDC="$candidate"
        break
    fi
done
if [ -z "$HDC" ]; then
    echo "❌ 未找到 hdc，请设置 PATH 或安装 OpenHarmony SDK。"
    exit 1
fi

HAP_DIR="entry/build/default/outputs/default"
HAP="$HAP_DIR/entry-default-signed.hap"
BUNDLE_NAME="com.youdroid.zhuobrowser"
MAIN_ABILITY="EntryAbility"
DEVICE_ID=""

print_usage() {
    echo "使用方法: ./run_release.sh [-d device-id]"
    echo "  -d device-id   直接指定目标设备（hdc list targets 中的序列号/IP）"
}

# 解析参数 -------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--device)
            if [ -z "${2:-}" ]; then
                echo "❌ 缺少 device-id"
                print_usage
                exit 1
            fi
            DEVICE_ID="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *) echo "❌ 未知的参数: $1"; print_usage; exit 1 ;;
    esac
done

list_devices() {
    "$HDC" list targets 2>/dev/null || true
}

select_device() {
    local targets
    targets=$(list_devices)

    if [ -z "$(echo "$targets" | awk 'NF')" ]; then
        echo "❌ 没有检测到已连接的 HarmonyOS 设备。"
        echo "请连接设备并授权 USB/网络调试，或使用 -d 指定 device-id。"
        exit 1
    fi

    local count
    count=$(echo "$targets" | awk 'NF { n++ } END { print n + 0 }')

    if [ "$count" -eq 1 ]; then
        DEVICE_ID=$(echo "$targets" | awk 'NF { print $1; exit }')
        return 0
    fi

    echo "🔍 检测到多个设备，请选择：" >&2
    local index=1
    while IFS= read -r target; do
        [ -z "$target" ] && continue
        echo "[$index] $target" >&2
        index=$((index + 1))
    done <<< "$targets"

    local choice
    printf '请选择设备编号 (1-%d，或 q 退出): ' "$count" >&2
    read -r choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
        exit 0
    fi

    if ! echo "$choice" | grep -Eq '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        echo "❌ 无效的选择: $choice" >&2
        exit 1
    fi

    DEVICE_ID=$(echo "$targets" | awk -v selected="$choice" 'NF { row++ } row == selected { print $1; exit }')
}

# 确认设备 -------------------------------------------------------------
if [ -z "$DEVICE_ID" ]; then
    select_device
fi
echo "📱 目标设备: $DEVICE_ID"

# 构建 release 包 ------------------------------------------------------
echo "🛠️  编译 Release 包 (hvigorw assembleHap)..."
"$HVIGORW" assembleHap

if [ ! -f "$HAP" ]; then
    echo "❌ 构建产物不存在: $HAP"
    echo "请检查 build-profile.json5 的签名配置（Release 模式需要签名才能安装）。"
    exit 1
fi
echo "✅ 构建完成: $HAP"

# 安装到设备 -----------------------------------------------------------
echo "📦 安装到 $DEVICE_ID ..."
"$HDC" -t "$DEVICE_ID" install -r "$HAP"

# 启动应用 -------------------------------------------------------------
echo "🚀 启动应用..."
"$HDC" -t "$DEVICE_ID" shell aa start \
    -a "$MAIN_ABILITY" \
    -b "$BUNDLE_NAME" || {
    echo "⚠️  安装成功，但启动应用失败（可手动点击图标启动）。"
}

echo "🎉 完成。"
