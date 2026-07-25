#!/usr/bin/env bash
set -euo pipefail
REPO=${RS_REPO:-wcwq99/realm}; REF=${RS_REF:-main}; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" -o "$TMP/rs.tar.gz"
tar -xzf "$TMP/rs.tar.gz" -C "$TMP"; SRC=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d|head -n1)
exec bash "$SRC/install.sh"
