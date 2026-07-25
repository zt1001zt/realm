#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"
help=$(RS_TEST_MODE=1 RS_ROOT=/tmp/rs-none bash "$DIR/bin/rs" --help); assert_true grep -q 'RS Manager' <<<"$help"
make_root; trap cleanup_root EXIT; export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_SYSCTL_FILE="$RS_ROOT/etc/sysctl.d/99-rs-manager.conf" RS_BACKUP_DIR="$RS_ROOT/backups"
bash "$DIR/bin/rs" singbox list >/dev/null; bash "$DIR/bin/rs" realm list >/dev/null; bash "$DIR/bin/rs" tune status >/dev/null
prefix="$RS_ROOT/install"; RS_PREFIX="$prefix" RS_SKIP_DEPS=1 bash "$DIR/install.sh"; assert_true test -x "$prefix/bin/rs"; assert_true test -x "$prefix/bin/sb"
finish
