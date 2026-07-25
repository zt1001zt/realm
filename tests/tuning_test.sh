#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/tuning.sh"
make_root; trap cleanup_root EXIT; export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_SYSCTL_FILE="$RS_ROOT/etc/sysctl.d/99-rs-manager.conf"; mkdir -p "$RS_ROOT/etc/sysctl.d"; echo keep=yes > "$RS_ROOT/etc/sysctl.conf"
assert_true bash -c 'source lib/modules/tuning.sh; rs_tune_render low | grep -q "tcp_congestion_control = bbr"'
rs_tune_apply standard; assert_true test -s "$RS_SYSCTL_FILE"; assert_eq "$(cat "$RS_ROOT/etc/sysctl.conf")" keep=yes
rs_tune_restore; assert_false test -e "$RS_SYSCTL_FILE"
finish
