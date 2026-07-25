#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$DIR/../tools:$PATH"
for test in core transaction singbox realm tuning diagnostics cli; do
  echo "== $test =="
  bash "$DIR/tests/${test}_test.sh"
done