#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/realm.sh"
make_root; trap cleanup_root EXIT
export RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_BACKUP_DIR="$RS_ROOT/backups"; mkdir -p "$(dirname "$RS_REALM_CONFIG")"; cp "$DIR/tests/fixtures/realm-existing.toml" "$RS_REALM_CONFIG"
rs_realm_add edge1 11000 target.example.com:21000
assert_eq "$(grep -c 'rs:id=edge1' "$RS_REALM_CONFIG")" 1
assert_true grep -q 'existing comment' "$RS_REALM_CONFIG"
rs_realm_edit edge1 11001 target.example.com:21001
assert_true grep -q 'listen = "\[::\]:11001"' "$RS_REALM_CONFIG"
rs_realm_toggle edge1 disabled; assert_true grep -q 'rs:disabled' "$RS_REALM_CONFIG"
rs_realm_toggle edge1 enabled; assert_false grep -q 'rs:disabled' "$RS_REALM_CONFIG"
rs_realm_add_range 12000 12002 range.example.com 22000
assert_eq "$(grep -c 'range.example.com:' "$RS_REALM_CONFIG")" 3
rs_realm_delete edge1; assert_false grep -q 'rs:id=edge1' "$RS_REALM_CONFIG"
assert_eq "$(rs_realm_parse_link 'hy2://pass@relay.example.com:443/?x=1')" $'relay.example.com\t443'
finish
