#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

VERSION=${1:?usage: build-release-bundle.sh VERSION [OUTPUT]}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid version' >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT=${2:-$ROOT/rs-manager-$VERSION.tar.gz}
case $OUTPUT in /*|[A-Za-z]:/*) ;; *) OUTPUT="$PWD/$OUTPUT";; esac
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
BUNDLE="rs-manager-v$VERSION"
mkdir -p "$WORK/$BUNDLE" "$(dirname "$OUTPUT")"

for item in install.sh realm.sh THIRD_PARTY_NOTICES.md checksums.txt bin lib; do
  cp -a "$ROOT/$item" "$WORK/$BUNDLE/"
done
find "$WORK/$BUNDLE" -type d -exec chmod 0755 {} +
find "$WORK/$BUNDLE" -type f -exec chmod 0644 {} +
chmod 0755 "$WORK/$BUNDLE/install.sh" "$WORK/$BUNDLE/realm.sh" "$WORK/$BUNDLE/bin/rs"

tmp_output="$OUTPUT.tmp-$$"
LC_ALL=C tar --sort=name --format=ustar --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner -C "$WORK" -cf - "$BUNDLE" | gzip -n -9 >"$tmp_output"
mv "$tmp_output" "$OUTPUT"
printf '%s\n' "$OUTPUT"
