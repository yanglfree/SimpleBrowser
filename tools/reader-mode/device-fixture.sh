#!/bin/sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixture_port=${ZHUO_READER_FIXTURE_PORT:-4173}
device_target=${1:-}

cd "$tool_dir"
node fixture-server.mjs &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT INT TERM

if [ -n "$device_target" ]; then
  hdc -t "$device_target" rport "tcp:$fixture_port" "tcp:$fixture_port"
else
  hdc rport "tcp:$fixture_port" "tcp:$fixture_port"
fi

printf '%s\n' "Open in ZhuoBrowser: http://127.0.0.1:$fixture_port/fixtures/wechat-long"
printf '%s\n' "Keep this process running during device QA. Press Ctrl-C when finished."
wait "$fixture_pid"
