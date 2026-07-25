#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$DIR/tests/test_helper.sh"
make_root; trap cleanup_root EXIT

assert_false grep -q '[*]rs-manager.sh$' "$DIR/checksums.txt"
assert_true grep -q 'releases/download/$REF/rs-manager-$VERSION.tar.gz' "$DIR/rs-manager.sh"
assert_true test -f "$DIR/scripts/build-release-bundle.sh"
if [[ -f $DIR/scripts/build-release-bundle.sh ]]; then
  assert_true bash "$DIR/scripts/build-release-bundle.sh" 1.0.0 "$RS_ROOT/one.tar.gz"
  assert_true bash "$DIR/scripts/build-release-bundle.sh" 1.0.0 "$RS_ROOT/two.tar.gz"
  assert_eq "$(sha256sum "$RS_ROOT/one.tar.gz" | awk '{print $1}')" "$(sha256sum "$RS_ROOT/two.tar.gz" | awk '{print $1}')"
  expected=$(sed -n 's/^EXPECTED_SHA256=//p' "$DIR/rs-manager.sh")
  assert_eq "$(sha256sum "$RS_ROOT/one.tar.gz" | awk '{print $1}')" "$expected"
  bundle_has_bootstrap(){ tar -tzf "$1" | grep -q '/rs-manager.sh$'; }
  assert_false bundle_has_bootstrap "$RS_ROOT/one.tar.gz"
fi
finish
