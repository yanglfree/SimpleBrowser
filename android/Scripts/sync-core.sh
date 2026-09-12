#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
js_source="$root/../core/js"
rules_source="$root/../core/rules/android-network.json"
js_target="$root/app/src/main/assets/js"
rules_target="$root/app/src/main/assets/rules"
if [ ! -d "$js_source" ] || [ ! -f "$rules_source" ]; then
  echo "missing core js/rules — run: cd core && npm run export-js && npm run export-rules" >&2
  exit 1
fi
mkdir -p "$js_target" "$rules_target"
rsync -a --delete "$js_source/" "$js_target/"
cp "$rules_source" "$rules_target/android-network.json"
echo "copied core/js and android-network.json into app/src/main/assets"
