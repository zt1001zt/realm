#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/tuning.sh"
make_root; trap cleanup_root EXIT; export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_SYSCTL_FILE="$RS_ROOT/etc/sysctl.d/99-rs-manager.conf"; mkdir -p "$RS_ROOT/etc/sysctl.d"; echo keep=yes > "$RS_ROOT/etc/sysctl.conf"
assert_true bash -c 'source lib/modules/tuning.sh; rs_tune_render low | grep -q "tcp_congestion_control = bbr"'
smart_preview=$(rs_tune_smart_preview)
assert_true grep -q '^kernel=' <<<"$smart_preview"
assert_true grep -q 'tcp_congestion_control = bbr' <<<"$smart_preview"
rs_tune_apply standard; assert_true test -s "$RS_SYSCTL_FILE"; assert_eq "$(cat "$RS_ROOT/etc/sysctl.conf")" keep=yes
rs_tune_realm; assert_true grep -q 'nf_conntrack_max = 262144' "$RS_SYSCTL_FILE"
assert_false test -e "$RS_ROOT/etc/sysctl.d/98-rs-realm.conf"
rs_tune_restore; assert_false test -e "$RS_SYSCTL_FILE"
assert_false test -e "$RS_ROOT/etc/sysctl.d/98-rs-realm.conf"
rs_tune_render standard >"$RS_ROOT/candidate-sysctl"
# shellcheck disable=SC2317 # Test override invoked indirectly by the module.
sysctl(){ return 0; }
ip(){ printf '%s\n' 'default via 192.0.2.1 dev eth0'; }
tc(){ : >"$RS_ROOT/tc-called"; return 1; }
RS_TEST_MODE=0 assert_true rs_tune_post_apply "$RS_ROOT/candidate-sysctl"
assert_false test -e "$RS_ROOT/tc-called"
mkdir -p "$RS_STATE_DIR"; printf '%s\n' original >"$RS_STATE_DIR/sysctl.original"; printf '%s\n' managed >"$RS_SYSCTL_FILE"; printf 'sysctl\tnet.core.default_qdisc\tpfifo_fast\n' >"$(rs_tune_runtime_file)"
sysctl(){ [[ -d ${RS_LOCK_DIR:-} ]] && : >"$RS_ROOT/restore-lock-seen"; return 1; }
assert_false env RS_TEST_MODE=0 bash -c 'source lib/core/common.sh; source lib/core/transaction.sh; source lib/core/state.sh; source lib/modules/tuning.sh; sysctl(){ [[ -d ${RS_LOCK_DIR:-} ]] && : >"$RS_ROOT/restore-lock-seen"; return 1; }; rs_tune_restore'
assert_true test -f "$RS_ROOT/restore-lock-seen"
assert_true test -f "$RS_STATE_DIR/sysctl.original"
assert_true test -f "$(rs_tune_runtime_file)"
rs_tune_prepare_original(){ [[ -d ${RS_LOCK_DIR:-} ]] && : >"$RS_ROOT/tune-lock-seen"; }
rs_tune_apply low
assert_true test -f "$RS_ROOT/tune-lock-seen"
finish
