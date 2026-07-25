#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/realm.sh"
make_root; trap cleanup_root EXIT
export RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_BACKUP_DIR="$RS_ROOT/backups"; mkdir -p "$(dirname "$RS_REALM_CONFIG")" "$(dirname "$RS_SINGBOX_CONFIG")"; cp "$DIR/tests/fixtures/realm-existing.toml" "$RS_REALM_CONFIG"
cat > "$RS_SINGBOX_CONFIG" <<'EOF'
{"inbounds":[{"type":"shadowsocks","tag":"occupied","listen_port":17000}]}
EOF
cat >>"$RS_REALM_CONFIG" <<'EOF'

# Unmanaged example; this is documentation, not a disabled rule.
# [[endpoints]]
# listen = "0.0.0.0:PORT"
# remote = "example.com:PORT"
EOF
printf '[network]\nno_tcp = [\n' >"$RS_ROOT/invalid.toml"
assert_false rs_realm_validate "$RS_ROOT/invalid.toml"
mkdir -p "$RS_ROOT/test-bin"
cat >"$RS_ROOT/test-bin/realm" <<EOF
#!/usr/bin/env sh
[ -n "\${REALM_CONF:-}" ] || exit 1
printf '%s' "\$REALM_CONF" | grep -q '"listen": "127.0.0.1:0"' || exit 1
: >'$RS_ROOT/realm-validator-seen'
printf '%s\n' 'log: validation'
EOF
chmod +x "$RS_ROOT/test-bin/realm"
PATH="$RS_ROOT/test-bin:$PATH" RS_TEST_MODE=0 assert_true rs_realm_validate "$RS_REALM_CONFIG"
assert_true test -f "$RS_ROOT/realm-validator-seen"
real_python=${RS_PYTHON:-$(command -v python3)}
cat >"$RS_ROOT/test-bin/python-fallback" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$2" | grep -q '^[[:space:]]*import toml$' || exit 1
exec '$real_python' "\$@"
EOF
chmod +x "$RS_ROOT/test-bin/python-fallback"
RS_PYTHON="$RS_ROOT/test-bin/python-fallback" assert_true rs_realm_validate "$RS_REALM_CONFIG"
rs_realm_migrate
assert_true grep -q '^# listen = "0.0.0.0:PORT"$' "$RS_REALM_CONFIG"
assert_true grep -q '^# rs:id=legacy-' "$RS_REALM_CONFIG"
assert_true bash -c 'source lib/modules/realm.sh; RS_REALM_CONFIG="$1"; rs_realm_list | grep -q "legacy-"' _ "$RS_REALM_CONFIG"
legacy_id=$(sed -n 's/^# rs:id=\(legacy-[^[:space:]]*\)$/\1/p' "$RS_REALM_CONFIG" | head -n1)
rs_realm_delete "$legacy_id"
assert_true grep -q '^\[custom\]' "$RS_REALM_CONFIG"
assert_true grep -q '^keep = "yes"' "$RS_REALM_CONFIG"
# shellcheck disable=SC2317 # Test override invoked indirectly by the module.
rs_port_is_used(){ [[ -d ${RS_LOCK_DIR:-} ]] && : >"$RS_ROOT/realm-lock-seen"; return 1; }
rs_realm_add edge1 11000 target.example.com:21000
assert_true test -f "$RS_ROOT/realm-lock-seen"
assert_eq "$(grep -c 'rs:id=edge1' "$RS_REALM_CONFIG")" 1
assert_true grep -q 'existing comment' "$RS_REALM_CONFIG"
before=$(sha256sum "$RS_REALM_CONFIG" | awk '{print $1}')
assert_false rs_realm_edit edge1 11002 target.example.com:70000
assert_eq "$(sha256sum "$RS_REALM_CONFIG" | awk '{print $1}')" "$before"
assert_false rs_realm_add duplicate-id 11000 target.example.com:21000
assert_false rs_realm_add singbox-port 17000 target.example.com:27000
sed -i '/remote = "target.example.com:21000"/a # edit-note' "$RS_REALM_CONFIG"
rs_realm_edit edge1 11001 target.example.com:21001
assert_true grep -q 'listen = "\[::\]:11001"' "$RS_REALM_CONFIG"
assert_true grep -q '^# edit-note' "$RS_REALM_CONFIG"
sed -i '/remote = "target.example.com:21001"/a # endpoint-note' "$RS_REALM_CONFIG"
sed -i '/remote = "target.example.com:21001"/a custom = [\n  "value",\n]' "$RS_REALM_CONFIG"
sed -i '/^# endpoint-note/i [endpoints.network]\nno_tcp = true\nuse_udp = false' "$RS_REALM_CONFIG"
rs_port_is_used(){ [[ $1 == 11001 ]]; }
rs_realm_toggle edge1 disabled; assert_true grep -q 'rs:disabled' "$RS_REALM_CONFIG"
assert_true "${RS_PYTHON:-python3}" -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$RS_REALM_CONFIG"
assert_true grep -q '^# rs:off   "value",$' "$RS_REALM_CONFIG"
assert_true grep -q '^# rs:off \[endpoints.network\]$' "$RS_REALM_CONFIG"
rs_realm_toggle edge1 enabled; assert_false grep -q 'rs:disabled' "$RS_REALM_CONFIG"
assert_true "${RS_PYTHON:-python3}" -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$RS_REALM_CONFIG"
assert_true grep -q '^  "value",$' "$RS_REALM_CONFIG"
assert_true grep -q '^\[endpoints.network\]$' "$RS_REALM_CONFIG"
assert_true grep -q '^# endpoint-note' "$RS_REALM_CONFIG"
rs_realm_add_range 12000 12002 range.example.com 22000
assert_eq "$(grep -c 'range.example.com:' "$RS_REALM_CONFIG")" 3
rs_realm_add blocker 13001 target.example.com:23001
assert_false rs_realm_add_range 13000 13002 range.example.com 23000
assert_false grep -q 'rs:id=range-13000' "$RS_REALM_CONFIG"
rs_realm_delete blocker
rs_realm_delete edge1; assert_false grep -q 'rs:id=edge1' "$RS_REALM_CONFIG"
assert_false rs_realm_delete does-not-exist
assert_eq "$(rs_realm_parse_link 'hy2://pass@relay.example.com:443/?x=1')" $'relay.example.com\t443'
finish
