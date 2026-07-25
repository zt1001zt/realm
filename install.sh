#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd); PREFIX=${RS_PREFIX:-/usr/local}; LIB="$PREFIX/lib/rs-manager"; BIN="$PREFIX/bin"
if [[ ${RS_SKIP_DEPS:-0} != 1 ]]; then
  [[ ${EUID:-1} -eq 0 ]]||{ echo 'Run as root';exit 1; }
  if command -v apk>/dev/null;then apk add --no-cache bash curl jq openssl ca-certificates iproute2;elif command -v apt-get>/dev/null;then apt-get update&&apt-get install -y bash curl jq openssl ca-certificates iproute2;elif command -v dnf>/dev/null;then dnf install -y bash curl jq openssl ca-certificates iproute;else yum install -y bash curl jq openssl ca-certificates iproute;fi
fi
if [[ -f "$SOURCE_DIR/checksums.txt" ]]&&command -v sha256sum>/dev/null;then (cd "$SOURCE_DIR"&&sha256sum -c checksums.txt);fi
mkdir -p "$LIB" "$BIN"; cp -R "$SOURCE_DIR/lib" "$SOURCE_DIR/bin" "$LIB/"; cp "$SOURCE_DIR/realm.sh" "$LIB/realm.sh"; cp "$SOURCE_DIR/THIRD_PARTY_NOTICES.md" "$LIB/"; chmod +x "$LIB/bin/rs"
printf '#!/usr/bin/env bash\nRS_LIB_DIR=%q exec bash %q "$@"\n' "$LIB" "$LIB/bin/rs" > "$BIN/rs"
printf '#!/usr/bin/env bash\nRS_LIB_DIR=%q exec bash %q singbox "${1:-menu}" "${@:2}"\n' "$LIB" "$LIB/bin/rs" > "$BIN/sb"
chmod +x "$BIN/rs" "$BIN/sb"; echo "Installed RS Manager: $BIN/rs (Sing-box shortcut: $BIN/sb)"
