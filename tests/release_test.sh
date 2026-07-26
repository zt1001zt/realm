#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$DIR/tests/test_helper.sh"
make_root; trap cleanup_root EXIT

assert_false grep -q '[*]rs-manager.sh$' "$DIR/checksums.txt"
assert_true grep -q 'RS_MANAGER_INSTALL_V1' "$DIR/install.sh"
assert_true grep -q 'releases/download/$REF/rs-manager-$VERSION.tar.gz' "$DIR/rs-manager.sh"
assert_true test -f "$DIR/scripts/build-release-bundle.sh"
release_version=$(sed -n 's/^VERSION=//p' "$DIR/rs-manager.sh")
assert_eq "$release_version" 1.0.4
assert_true grep -q 'v1.0.4/rs-manager.sh' "$DIR/README.md"
assert_true grep -q '一键卸载 RS Manager' "$DIR/README.md"
assert_true grep -q '系统不支持.*跳过' "$DIR/README.md"

while read -r expected entry; do
  path=${entry#\*}
  actual=$(git -c safe.directory="$DIR" -C "$DIR" cat-file blob "HEAD:$path" | sha256sum | awk '{print $1}')
  assert_eq "$actual" "$expected"
done <"$DIR/checksums.txt"

rocky_setup=$(awk '/image: rockylinux:9/{getline; print}' "$DIR/.github/workflows/rs-manager.yml")
assert_false grep -Eq '(^|[[:space:]])(coreutils|curl)([[:space:]]|$)' <<<"$rocky_setup"

if [[ -f $DIR/scripts/build-release-bundle.sh ]]; then
  mkdir -p "$RS_ROOT/canonical" "$RS_ROOT/crlf"
  for item in install.sh realm.sh THIRD_PARTY_NOTICES.md checksums.txt bin lib scripts; do
    cp -a "$DIR/$item" "$RS_ROOT/canonical/"
  done
  find "$RS_ROOT/canonical" -type f -exec sed -i 's/\r$//' {} +
  cp -a "$RS_ROOT/canonical/." "$RS_ROOT/crlf/"
  find "$RS_ROOT/crlf" -path "$RS_ROOT/crlf/scripts" -prune -o -type f -exec sed -i 's/$/\r/' {} +
  assert_true bash "$RS_ROOT/canonical/scripts/build-release-bundle.sh" "$release_version" "$RS_ROOT/canonical.tar.gz"
  assert_true bash "$RS_ROOT/crlf/scripts/build-release-bundle.sh" "$release_version" "$RS_ROOT/crlf.tar.gz"
  assert_eq "$(sha256sum "$RS_ROOT/canonical.tar.gz" | awk '{print $1}')" "$(sha256sum "$RS_ROOT/crlf.tar.gz" | awk '{print $1}')"

  assert_true bash "$DIR/scripts/build-release-bundle.sh" "$release_version" "$RS_ROOT/one.tar.gz"
  assert_true bash "$DIR/scripts/build-release-bundle.sh" "$release_version" "$RS_ROOT/two.tar.gz"
  assert_eq "$(sha256sum "$RS_ROOT/one.tar.gz" | awk '{print $1}')" "$(sha256sum "$RS_ROOT/two.tar.gz" | awk '{print $1}')"
  expected=$(sed -n 's/^EXPECTED_SHA256=//p' "$DIR/rs-manager.sh")
  actual=$(sha256sum "$RS_ROOT/one.tar.gz" | awk '{print $1}')
  assert_eq 64 "${#expected}"
  assert_false grep -q '[^0-9a-f]' <<<"$expected"
  assert_eq "$actual" "$expected"
  bundle_has_bootstrap(){ tar -tzf "$1" | grep -q '/rs-manager.sh$'; }
  assert_false bundle_has_bootstrap "$RS_ROOT/one.tar.gz"
fi
finish
