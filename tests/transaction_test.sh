#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; source "$DIR/lib/core/common.sh"; source "$DIR/lib/core/transaction.sh"; source "$DIR/lib/core/state.sh"
make_root; trap cleanup_root EXIT
export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_BACKUP_DIR="$RS_ROOT/backups" RS_LOCK_DIR="$RS_ROOT/run/rs.lock"
rs_state_init; rs_state_set '.hello' 'world'; assert_eq "$(rs_state_get '.hello')" world
if [[ $(uname -s) != MINGW* ]]; then assert_eq "$(stat -c '%a' "$(rs_state_file)")" 600; fi
echo old > "$RS_ROOT/target"; echo new > "$RS_ROOT/candidate"; rs_atomic_install "$RS_ROOT/candidate" "$RS_ROOT/target"; assert_eq "$(cat "$RS_ROOT/target")" new
validator_fail(){ return 1; }
post_fail(){ [[ ${RS_TRANSACTION_ROLLBACK:-0} == 1 ]] && return 0; return 1; }
echo stable > "$RS_ROOT/target"; echo invalid > "$RS_ROOT/candidate"
assert_false rs_transaction_apply "$RS_ROOT/candidate" "$RS_ROOT/target" validator_fail
assert_eq "$(cat "$RS_ROOT/target")" stable
echo replacement > "$RS_ROOT/candidate"
assert_false rs_transaction_apply "$RS_ROOT/candidate" "$RS_ROOT/target" true post_fail
assert_eq "$(cat "$RS_ROOT/target")" stable
echo state-old > "$RS_ROOT/state-target"; echo config-new > "$RS_ROOT/candidate"; echo state-new > "$RS_ROOT/state-candidate"
assert_false rs_transaction_apply_pair "$RS_ROOT/candidate" "$RS_ROOT/target" "$RS_ROOT/state-candidate" "$RS_ROOT/state-target" true post_fail
assert_eq "$(cat "$RS_ROOT/target")" stable
assert_eq "$(cat "$RS_ROOT/state-target")" state-old
assert_true rs_transaction_apply_pair "$RS_ROOT/candidate" "$RS_ROOT/target" "$RS_ROOT/state-candidate" "$RS_ROOT/state-target" true true
assert_eq "$(cat "$RS_ROOT/target")" config-new
assert_eq "$(cat "$RS_ROOT/state-target")" state-new
assert_true rs_lock_acquire
assert_true rs_lock_acquire
rs_lock_release
assert_true test -d "$RS_LOCK_DIR"
rs_lock_release
assert_false test -d "$RS_LOCK_DIR"
mkdir -p "$RS_LOCK_DIR"; printf '%s\n' 999999 >"$RS_LOCK_DIR/pid"
assert_true rs_lock_acquire
rs_lock_release
assert_false bash -c 'set -e; source lib/core/common.sh; source lib/core/transaction.sh; RS_LOCK_DIR=$1; rs_locked_call false' _ "$RS_LOCK_DIR"
assert_false test -d "$RS_LOCK_DIR"
mkdir -p "$RS_ROOT/rollback-failure"; printf 'old\n' >"$RS_ROOT/rollback-failure/target"; printf 'new\n' >"$RS_ROOT/rollback-failure/candidate"
assert_false bash -c 'source lib/core/common.sh; source lib/core/transaction.sh; RS_LOCK_DIR=$1; RS_BACKUP_DIR=$2; calls=0; rs_atomic_install(){ calls=$((calls+1)); if ((calls==1)); then cp "$1" "$2"; else return 1; fi; }; post_fail(){ [[ ${RS_TRANSACTION_ROLLBACK:-0} == 1 ]] && return 0; return 1; }; rs_transaction_apply "$3" "$4" true post_fail' _ "$RS_ROOT/rollback-failure/lock.lock" "$RS_ROOT/rollback-failure/backups" "$RS_ROOT/rollback-failure/candidate" "$RS_ROOT/rollback-failure/target"
assert_true bash -c 'compgen -G "$1/.rs-rollback.*" >/dev/null' _ "$RS_ROOT/rollback-failure"
for i in $(seq 1 12); do echo "$i" > "$RS_ROOT/f$i"; rs_backup_create auto "$RS_ROOT/f$i" >/dev/null; sleep 0.01; done
rs_backup_rotate; assert_eq "$(find "$RS_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'auto-*' | wc -l | tr -d ' ')" 10
finish
