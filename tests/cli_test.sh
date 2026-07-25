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
