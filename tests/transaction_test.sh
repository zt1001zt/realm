#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; source "$DIR/lib/core/common.sh"; source "$DIR/lib/core/transaction.sh"; source "$DIR/lib/core/state.sh"
make_root; trap cleanup_root EXIT
export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_BACKUP_DIR="$RS_ROOT/backups" RS_LOCK_DIR="$RS_ROOT/run/rs.lock"
rs_state_init; rs_state_set '.hello' 'world'; assert_eq "$(rs_state_get '.hello')" world
echo old > "$RS_ROOT/target"; echo new > "$RS_ROOT/candidate"; rs_atomic_install "$RS_ROOT/candidate" "$RS_ROOT/target"; assert_eq "$(cat "$RS_ROOT/target")" new
for i in $(seq 1 12); do echo "$i" > "$RS_ROOT/f$i"; rs_backup_create auto "$RS_ROOT/f$i" >/dev/null; sleep 0.01; done
rs_backup_rotate; assert_eq "$(find "$RS_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'auto-*' | wc -l | tr -d ' ')" 10
finish
