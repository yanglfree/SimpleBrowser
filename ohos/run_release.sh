#!/usr/bin/env zsh
exec "$(cd "$(dirname "$0")/.." && pwd)/run_release.sh" ohos "$@"
