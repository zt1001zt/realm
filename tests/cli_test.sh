#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"
help=$(RS_TEST_MODE=1 RS_ROOT=/tmp/rs-none bash "$DIR/bin/rs" --help); assert_true grep -q 'RS Manager' <<<"$help"
assert_true grep -q 'service install|upgrade|start|stop|restart|status' <<<"$help"
assert_true sh -n "$DIR/rs-manager.sh"
make_root; trap cleanup_root EXIT; export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_SYSCTL_FILE="$RS_ROOT/etc/sysctl.d/99-rs-manager.conf" RS_BACKUP_DIR="$RS_ROOT/backups"
bash "$DIR/bin/rs" singbox list >/dev/null; bash "$DIR/bin/rs" realm list >/dev/null; bash "$DIR/bin/rs" tune status >/dev/null
sb_menu=$(printf '0\n' | bash "$DIR/bin/rs" singbox menu); assert_true grep -q 'clone' <<<"$sb_menu"
realm_menu=$(printf '0\n' | bash "$DIR/bin/rs" realm menu); assert_true grep -q 'edit' <<<"$realm_menu"
cat >"$RS_ROOT/etc/os-release" <<'EOF'
ID=alpine
EOF
mkdir -p "$RS_ROOT/test-bin"
cat >"$RS_ROOT/test-bin/rc-service" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$*" >'$RS_ROOT/rc-service.log'
EOF
chmod +x "$RS_ROOT/test-bin/rc-service"
PATH="$RS_ROOT/test-bin:$PATH" bash "$DIR/bin/rs" service status realm
assert_eq "$(cat "$RS_ROOT/rc-service.log")" 'realm status'
mkdir -p "$RS_ROOT/menu-bin"
cp "$DIR/../tools/jq.exe" "$RS_ROOT/menu-bin/jq.exe"
cat >"$RS_ROOT/menu-install-hook" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$1" >"$RS_ROOT/menu-install.log"
EOF
chmod +x "$RS_ROOT/menu-install-hook"
printf '2\ny\nss\nmenu-test\n23456\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-hook" bash "$DIR/bin/rs" singbox menu >/dev/null
hook_component=$(cat "$RS_ROOT/menu-install.log" 2>/dev/null || true)
assert_eq "$hook_component" sing-box
assert_true jq -e '.inbounds[]|select(.type=="shadowsocks" and .listen_port==23456)' "$RS_SINGBOX_CONFIG"
refusal_warning=$'\xe8\xaf\xb7\xe5\x85\x88\xe5\xae\x89\xe8\xa3\x85\xef\xbc\x9ars service install sing-box'
refusal_output=$(printf '2\nn\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" bash "$DIR/bin/rs" singbox menu 2>&1)
assert_true grep -Fq "$refusal_warning" <<<"$refusal_output"
cat >"$RS_ROOT/menu-install-fail-hook" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
chmod +x "$RS_ROOT/menu-install-fail-hook"
install_failure_warning=$'Sing-box \xe5\xae\x89\xe8\xa3\x85\xe5\xa4\xb1\xe8\xb4\xa5\xef\xbc\x8c\xe5\xb7\xb2\xe5\x8f\x96\xe6\xb6\x88\xe5\xbd\x93\xe5\x89\x8d\xe6\x93\x8d\xe4\xbd\x9c'
install_failure_output=$(printf '2\ny\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-fail-hook" bash "$DIR/bin/rs" singbox menu 2>&1)
assert_true grep -Fq "$install_failure_warning" <<<"$install_failure_output"
rm -f "$RS_ROOT/menu-install.log"
PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-hook" bash "$DIR/bin/rs" singbox add ss cli-test 23457 >/dev/null
assert_false test -e "$RS_ROOT/menu-install.log"
prefix="$RS_ROOT/install"; RS_PREFIX="$prefix" RS_SKIP_DEPS=1 bash "$DIR/install.sh"; assert_true test -x "$prefix/bin/rs"; assert_true test -x "$prefix/bin/sb"
printf '%s\n' old-library >"$prefix/lib/rs-manager/old-marker"; printf '#!/usr/bin/env bash\necho old-wrapper\n' >"$prefix/bin/rs"; chmod +x "$prefix/bin/rs"
old_wrapper=$(sha256sum "$prefix/bin/rs" | awk '{print $1}')
assert_false env RS_PREFIX="$prefix" RS_SKIP_DEPS=1 RS_INSTALL_INJECT_FAILURE=after-swap bash "$DIR/install.sh"
assert_eq "$(cat "$prefix/lib/rs-manager/old-marker")" old-library
assert_eq "$(sha256sum "$prefix/bin/rs" | awk '{print $1}')" "$old_wrapper"
assert_false env RS_PREFIX="$prefix" RS_SKIP_DEPS=1 RS_INSTALL_INJECT_FAILURE=after-capture bash "$DIR/install.sh"
assert_eq "$(cat "$prefix/lib/rs-manager/old-marker")" old-library
assert_eq "$(sha256sum "$prefix/bin/rs" | awk '{print $1}')" "$old_wrapper"
assert_false env RS_PREFIX="$prefix" RS_SKIP_DEPS=1 RS_INSTALL_INJECT_FAILURE=rollback-restore bash "$DIR/install.sh"
assert_true bash -c 'compgen -G "$1/lib/.rs-manager.old-*" >/dev/null' _ "$prefix"
finish
