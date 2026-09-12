#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
source="$root/../core/js"
target="$root/ZhuoBrowser/Resources/js"
if [ ! -d "$source" ]; then
  echo "missing $source — build zhuobrowser-core first" >&2
  exit 1
fi
mkdir -p "$target"
rsync -a --delete "$source/" "$target/"
echo "copied core/js -> ZhuoBrowser/Resources/js"
