#!/bin/sh
set -eu

REPO=${RS_REPO:-zt1001zt/realm}
VERSION=1.0.2
REF=${RS_REF:-v$VERSION}
EXPECTED_SHA256=c4fcf0d63f55a3362aade3aff8ec3c83f688ef0aa11344ab810aaeb385052a99
if [ "$REF" != "v$VERSION" ]; then
  [ -n "${RS_BUNDLE_SHA256:-}" ] || { echo 'RS_BUNDLE_SHA256 is required with a custom RS_REF' >&2; exit 1; }
  VERSION=${REF#v}
  EXPECTED_SHA256=$RS_BUNDLE_SHA256
fi
case $EXPECTED_SHA256 in *[!0-9a-f]*|'') echo 'Invalid bundle SHA-256' >&2; exit 1;; esac
[ "${#EXPECTED_SHA256}" -eq 64 ] || { echo 'Invalid bundle SHA-256 length' >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
URL="https://github.com/$REPO/releases/download/$REF/rs-manager-$VERSION.tar.gz"
if command -v curl >/dev/null 2>&1; then
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 "$URL" -o "$TMP/rs-manager.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP/rs-manager.tar.gz" "$URL"
else
  echo 'curl or wget is required' >&2; exit 1
fi
command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required' >&2; exit 1; }
printf '%s  %s\n' "$EXPECTED_SHA256" "$TMP/rs-manager.tar.gz" | sha256sum -c -
if tar -tzf "$TMP/rs-manager.tar.gz" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then echo 'Unsafe bundle paths' >&2; exit 1; fi
tar -xzf "$TMP/rs-manager.tar.gz" -C "$TMP"
SRC="$TMP/rs-manager-v$VERSION"
[ -f "$SRC/install.sh" ] || { echo 'Invalid RS Manager bundle' >&2; exit 1; }
RS_LAUNCH=1 exec bash "$SRC/install.sh"
