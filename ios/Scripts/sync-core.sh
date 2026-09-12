#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
js_source="$root/../core/js"
rules_source="$root/../core/rules"
js_target="$root/ZhuoBrowser/Resources/js"
rules_target="$root/ZhuoBrowser/Resources/rules"
if [ ! -d "$js_source" ]; then
  echo "missing $js_source — build zhuobrowser-core first" >&2
  exit 1
fi
mkdir -p "$js_target" "$rules_target"
rsync -a --delete "$js_source/" "$js_target/"
if [ -d "$rules_source" ]; then
  rsync -a --delete --exclude README.md "$rules_source/" "$rules_target/"
fi
echo "copied core/js and core/rules into ZhuoBrowser/Resources"
