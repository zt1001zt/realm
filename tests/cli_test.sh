#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"
help=$(RS_TEST_MODE=1 RS_ROOT=/tmp/rs-none bash "$DIR/bin/rs" --help); assert_true grep -q 'RS Manager' <<<"$help"
assert_true grep -q 'service install|upgrade|start|stop|restart|status' <<<"$help"
assert_true sh -n "$DIR/rs-manager.sh"
make_root; trap cleanup_root EXIT; export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml" RS_SYSCTL_FILE="$RS_ROOT/etc/sysctl.d/99-rs-manager.conf" RS_BACKUP_DIR="$RS_ROOT/backups"
bash "$DIR/bin/rs" singbox list >/dev/null; bash "$DIR/bin/rs" realm list >/dev/null; bash "$DIR/bin/rs" tune status >/dev/null
sb_menu=$(printf '0\n' | bash "$DIR/bin/rs" singbox menu); assert_true grep -Fq $'Sing-box \xe7\xae\xa1\xe7\x90\x86' <<<"$sb_menu"
assert_true grep -Fq $'5. \xe5\x85\x8b\xe9\x9a\x86\xe5\x85\xa5\xe7\xab\x99' <<<"$sb_menu"
realm_menu=$(printf '0\n' | bash "$DIR/bin/rs" realm menu); assert_true grep -Fq $'Realm \xe7\xae\xa1\xe7\x90\x86' <<<"$realm_menu"
assert_true grep -Fq $'3. \xe7\xbc\x96\xe8\xbe\x91\xe8\xa7\x84\xe5\x88\x99' <<<"$realm_menu"
cn_menu=$(printf '0\n' | bash "$DIR/bin/rs")
assert_true grep -Fq $'RS Manager \xe4\xb8\x80\xe9\x94\xae\xe7\xae\xa1\xe7\x90\x86\xe8\x84\x9a\xe6\x9c\xac' <<<"$cn_menu"
assert_true grep -Fq $'BBR/TCP \xe6\x99\xba\xe8\x83\xbd\xe8\xb0\x83\xe4\xbc\x98' <<<"$cn_menu"
rm -f "$RS_SYSCTL_FILE"
tune_declined=$(printf '3\n2\nn\n0\n' | bash "$DIR/bin/rs" 2>&1)
assert_true grep -q '^kernel=' <<<"$tune_declined"
assert_true grep -q 'tcp_congestion_control = bbr' <<<"$tune_declined"
assert_false test -e "$RS_SYSCTL_FILE"
printf '3\n2\ny\n0\n' | bash "$DIR/bin/rs" >/dev/null
assert_true test -s "$RS_SYSCTL_FILE"
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
ln -s "$(command -v jq)" "$RS_ROOT/menu-bin/jq"
cat >"$RS_ROOT/menu-install-hook" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$1" >"$RS_ROOT/menu-install.log"
EOF
chmod +x "$RS_ROOT/menu-install-hook"
menu_add_output=$(printf '2\ny\n1\nmenu-test\n23456\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_SB_HOST_OVERRIDE=198.51.100.20 RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-hook" bash "$DIR/bin/rs" singbox menu)
hook_component=$(cat "$RS_ROOT/menu-install.log" 2>/dev/null || true)
assert_eq "$hook_component" sing-box
assert_true jq -e '.inbounds[]|select(.type=="shadowsocks" and .listen_port==23456)' "$RS_SINGBOX_CONFIG"
assert_true grep -Eq 'ss://[^@]+@198\.51\.100\.20:23456#' <<<"$menu_add_output"
invalid_protocol_output=$(printf '2\ny\n9\n0\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_MENU_INSTALL_HOOK="$RS_ROOT/menu-install-hook" bash "$DIR/bin/rs" singbox menu 2>&1)
assert_true grep -Fq '无效的协议选项' <<<"$invalid_protocol_output"
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
assert_eq "$(jq '[.inbounds[]|select(.type=="shadowsocks")]|length' "$RS_SINGBOX_CONFIG")" 2
view_output=$(printf '1\n1\n0\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_SB_HOST_OVERRIDE=198.51.100.20 bash "$DIR/bin/rs" singbox menu)
assert_true grep -Fq '名称：menu-test' <<<"$view_output"
assert_true grep -Fq '端口：23456' <<<"$view_output"
assert_true grep -Fq '分享链接：' <<<"$view_output"
assert_true grep -Eq 'ss://[^@]+@198\.51\.100\.20:23456#' <<<"$view_output"
manual_host_output=$(printf '1\n1\nmanual.example.com\n0\n0\n' | PATH="$RS_ROOT/menu-bin:/usr/bin:/bin" RS_SB_DISABLE_HOST_DETECT=1 bash "$DIR/bin/rs" singbox menu)
assert_true grep -q '@manual\.example\.com:23456#' <<<"$manual_host_output"
prefix="$RS_ROOT/install"; RS_PREFIX="$prefix" RS_SKIP_DEPS=1 bash "$DIR/install.sh"; assert_true test -x "$prefix/bin/rs"; assert_true test -x "$prefix/bin/sb"
assert_eq "$(cat "$prefix/lib/rs-manager/.rs-manager-install" 2>/dev/null || true)" RS_MANAGER_INSTALL_V1
mkdir -p "$RS_ROOT/etc/sing-box" "$RS_ROOT/root/.realm" "$RS_ROOT/etc/rs-manager" "$RS_ROOT/backups" "$(dirname "$RS_SYSCTL_FILE")"
printf keep >"$RS_ROOT/etc/sing-box/config.json"
printf keep >"$RS_ROOT/root/.realm/config.toml"
printf keep >"$RS_ROOT/etc/rs-manager/state.json"
printf keep >"$RS_ROOT/backups/keep"
printf keep >"$RS_SYSCTL_FILE"
printf '7\ny\n' | RS_PREFIX="$prefix" RS_ROOT="$RS_ROOT" "$prefix/bin/rs" >/dev/null
assert_false test -e "$prefix/bin/rs"
assert_false test -e "$prefix/bin/sb"
assert_false test -e "$prefix/lib/rs-manager"
assert_eq "$(cat "$RS_ROOT/etc/sing-box/config.json")" keep
assert_eq "$(cat "$RS_ROOT/root/.realm/config.toml")" keep
assert_eq "$(cat "$RS_ROOT/etc/rs-manager/state.json")" keep
assert_eq "$(cat "$RS_ROOT/backups/keep")" keep
assert_eq "$(cat "$RS_SYSCTL_FILE")" keep
unsafe_prefix="$RS_ROOT/unsafe-install"
mkdir -p "$unsafe_prefix/bin" "$unsafe_prefix/lib/rs-manager"
printf '#!/usr/bin/env bash\n' >"$unsafe_prefix/bin/rs"
printf '#!/usr/bin/env bash\n' >"$unsafe_prefix/bin/sb"
printf wrong >"$unsafe_prefix/lib/rs-manager/.rs-manager-install"
assert_false env RS_PREFIX="$unsafe_prefix" bash "$DIR/bin/rs" manager uninstall
assert_true test -e "$unsafe_prefix/bin/rs"
assert_true test -e "$unsafe_prefix/bin/sb"
assert_true test -e "$unsafe_prefix/lib/rs-manager"
RS_PREFIX="$prefix" RS_SKIP_DEPS=1 bash "$DIR/install.sh"
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
