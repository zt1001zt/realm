#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd)
export PATH="/usr/bin:/bin:$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"
source "$DIR/lib/core/common.sh"
source "$DIR/lib/core/system.sh"
source "$DIR/lib/core/validation.sh"
source "$DIR/lib/core/service.sh"
make_root
trap cleanup_root EXIT
cat > "$RS_ROOT/etc/os-release" <<'EOF'
ID=debian
ID_LIKE=debian
EOF
rs_detect_platform
assert_eq "$RS_OS_FAMILY" debian
assert_eq "$RS_PACKAGE_MANAGER" apt
assert_eq "$RS_INIT_SYSTEM" systemd
cat > "$RS_ROOT/etc/os-release" <<'EOF'
ID=alpine
EOF
rs_detect_platform
assert_eq "$RS_OS_FAMILY" alpine
assert_eq "$RS_PACKAGE_MANAGER" apk
assert_eq "$RS_INIT_SYSTEM" openrc
assert_true rs_validate_port 443
assert_false rs_validate_port 0
assert_false rs_validate_port 65536
assert_true rs_validate_host 1.1.1.1
assert_true rs_validate_host example.com
assert_true rs_validate_host 2001:db8::1
assert_false rs_validate_host 'bad host'
mkdir -p "$RS_ROOT/test-bin"
cat > "$RS_ROOT/test-bin/systemctl" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$*" >>'$RS_ROOT/service.log'
EOF
cat > "$RS_ROOT/test-bin/rc-service" <<EOF
#!/usr/bin/env sh
printf 'rc-service %s\n' "\$*" >>'$RS_ROOT/service.log'
EOF
cat > "$RS_ROOT/test-bin/rc-update" <<EOF
#!/usr/bin/env sh
printf 'rc-update %s\n' "\$*" >>'$RS_ROOT/service.log'
EOF
chmod +x "$RS_ROOT/test-bin/"*
export PATH="$RS_ROOT/test-bin:$PATH"
RS_INIT_SYSTEM=systemd rs_service daemon-reload sing-box
assert_eq "$(tail -n1 "$RS_ROOT/service.log")" daemon-reload
RS_INIT_SYSTEM=systemd rs_service restart realm
assert_eq "$(tail -n1 "$RS_ROOT/service.log")" 'restart realm'
RS_INIT_SYSTEM=openrc rs_service enable realm
assert_eq "$(tail -n1 "$RS_ROOT/service.log")" 'rc-update add realm default'
export RS_REALM_CONFIG="$RS_ROOT/realm-port.toml"
cat >"$RS_REALM_CONFIG" <<'EOF'
[network]
# rs:id=managed
[[endpoints]]
listen = "[::]:19000"
remote = "one.example.com:29000"
[[endpoints]]
listen = "[::]:19001"
remote = "two.example.com:29001"
EOF
assert_true rs_port_in_realm 19001 managed
finish
