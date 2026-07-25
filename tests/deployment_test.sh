#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/singbox.sh"; source "$DIR/lib/modules/realm.sh"; source "$DIR/lib/modules/deployment.sh"
make_root; trap cleanup_root EXIT
export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_BACKUP_DIR="$RS_ROOT/backups" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_INIT_SYSTEM=systemd RS_OS_FAMILY=debian RS_ARCH_OVERRIDE=amd64
mkdir -p "$RS_ROOT/assets/sing-box-test" "$RS_ROOT/assets/realm-test"
printf '#!/usr/bin/env sh\necho sing-box test\n' >"$RS_ROOT/assets/sing-box-test/sing-box"; chmod +x "$RS_ROOT/assets/sing-box-test/sing-box"
printf '#!/usr/bin/env sh\necho realm test\n' >"$RS_ROOT/assets/realm-test/realm"; chmod +x "$RS_ROOT/assets/realm-test/realm"
tar -czf "$RS_ROOT/sing-box.tar.gz" -C "$RS_ROOT/assets" sing-box-test
tar -czf "$RS_ROOT/realm.tar.gz" -C "$RS_ROOT/assets" realm-test
rs_component_asset(){ case $1 in sing-box) printf 'test\tfile://%s\t%s\n' "$RS_ROOT/sing-box.tar.gz" "$(sha256sum "$RS_ROOT/sing-box.tar.gz"|awk '{print $1}')";; realm) printf 'test\tfile://%s\t%s\n' "$RS_ROOT/realm.tar.gz" "$(sha256sum "$RS_ROOT/realm.tar.gz"|awk '{print $1}')";; esac; }
rs_component_install sing-box
assert_true test -x "$RS_ROOT/usr/local/bin/sing-box"
assert_true test -f "$RS_ROOT/etc/systemd/system/sing-box.service"
assert_true grep -q 'ExecStart=.*/usr/local/bin/sing-box run -c' "$RS_ROOT/etc/systemd/system/sing-box.service"
assert_true jq -e '.inbounds|type=="array"' "$RS_SINGBOX_CONFIG"
rs_component_install realm
assert_true test -x "$RS_ROOT/usr/local/bin/realm"
assert_true test -f "$RS_ROOT/etc/systemd/system/realm.service"
assert_true grep -q 'ExecStart=.*/usr/local/bin/realm -c' "$RS_ROOT/etc/systemd/system/realm.service"
assert_true grep -q '^\[network\]' "$RS_REALM_CONFIG"
printf 'keep-old\n' >"$RS_ROOT/usr/local/bin/realm"; bad_asset(){ printf 'test\tfile://%s\t%s\n' "$RS_ROOT/realm.tar.gz" deadbeef; }; rs_component_asset(){ bad_asset; }
assert_false rs_component_install realm
assert_eq "$(cat "$RS_ROOT/usr/local/bin/realm")" keep-old
RS_INIT_SYSTEM=openrc rs_component_write_service realm
assert_true test -x "$RS_ROOT/etc/init.d/realm"
export RS_TEST_MODE=0 RS_INIT_SYSTEM=systemd RS_COMPONENT_ACTIVE=realm
: >"$RS_ROOT/service.log"
rs_service_exists(){ return 0; }
rs_service(){ printf '%s\n' "$*" >>"$RS_ROOT/service.log"; case $1 in is-enabled|is-active) return 1;; *) return 0;; esac; }
rs_component_capture_service_state realm
printf 'old-binary\n' >"$RS_ROOT/old-component"; printf 'new-binary\n' >"$RS_ROOT/new-component"
assert_false rs_transaction_apply "$RS_ROOT/new-component" "$RS_ROOT/old-component" true rs_component_post_apply
assert_eq "$(cat "$RS_ROOT/old-component")" old-binary
assert_true grep -q '^disable realm$' "$RS_ROOT/service.log"
assert_true grep -q '^stop realm$' "$RS_ROOT/service.log"
export RS_INIT_SYSTEM=openrc RS_COMPONENT_WAS_ENABLED=true RS_COMPONENT_WAS_ACTIVE=true RS_TRANSACTION_ROLLBACK=1
: >"$RS_ROOT/service.log"; rs_component_post_apply
assert_true grep -q '^enable realm$' "$RS_ROOT/service.log"
assert_true grep -q '^start realm$' "$RS_ROOT/service.log"
rs_service(){ return 1; }
assert_false rs_component_post_apply
finish
