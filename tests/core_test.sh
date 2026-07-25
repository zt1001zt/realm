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
finish
