#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX=${RS_PREFIX:-/usr/local}
LIB="$PREFIX/lib/rs-manager"
BIN="$PREFIX/bin"

if [[ ${RS_SKIP_DEPS:-0} != 1 ]]; then
  [[ ${EUID:-1} -eq 0 ]] || { echo 'Run as root'; exit 1; }
  if command -v apk >/dev/null; then
    apk add --no-cache bash curl jq openssl ca-certificates iproute2 python3 py3-tomli
  elif command -v apt-get >/dev/null; then
    apt-get update
    apt-get install -y bash curl jq openssl ca-certificates iproute2 python3 python3-toml
  elif command -v dnf >/dev/null; then
    dnf install -y bash curl jq openssl ca-certificates iproute python3.11
  else
    yum install -y bash curl jq openssl ca-certificates iproute python3.11
  fi
fi

command -v sha256sum >/dev/null || { echo 'sha256sum is required' >&2; exit 1; }
[[ -f "$SOURCE_DIR/checksums.txt" ]] || { echo 'checksums.txt is missing' >&2; exit 1; }
(cd "$SOURCE_DIR" && sha256sum -c checksums.txt)

mkdir -p "$PREFIX/lib" "$BIN"
stage_lib="$PREFIX/lib/.rs-manager.new-$$"
stage_rs="$BIN/.rs.new-$$"
stage_sb="$BIN/.sb.new-$$"
old_lib="$PREFIX/lib/.rs-manager.old-$$"
old_rs="$BIN/.rs.old-$$"
old_sb="$BIN/.sb.old-$$"
swapped=0
had_lib=0; had_rs=0; had_sb=0

cleanup_install(){
  local rc=$? rollback_rc=0
  trap - EXIT
  set +e
  if ((swapped)); then
    if rm -rf "$LIB"; then
      if ((had_lib)) && [[ ${RS_INSTALL_INJECT_FAILURE:-} != rollback-restore ]]; then mv "$old_lib" "$LIB" || rollback_rc=1; elif ((had_lib)); then rollback_rc=1; fi
    else rollback_rc=1; fi
    if rm -f "$BIN/rs"; then
      if ((had_rs)) && [[ ${RS_INSTALL_INJECT_FAILURE:-} != rollback-restore ]]; then mv "$old_rs" "$BIN/rs" || rollback_rc=1; elif ((had_rs)); then rollback_rc=1; fi
    else rollback_rc=1; fi
    if rm -f "$BIN/sb"; then
      if ((had_sb)) && [[ ${RS_INSTALL_INJECT_FAILURE:-} != rollback-restore ]]; then mv "$old_sb" "$BIN/sb" || rollback_rc=1; elif ((had_sb)); then rollback_rc=1; fi
    else rollback_rc=1; fi
  fi
  rm -rf "$stage_lib"; rm -f "$stage_rs" "$stage_sb"
  if ((rollback_rc)); then
    echo "ERROR: RS Manager rollback incomplete; recovery artifacts: $old_lib $old_rs $old_sb" >&2
    exit 70
  fi
  rm -rf "$old_lib"; rm -f "$old_rs" "$old_sb"
  exit "$rc"
}
trap cleanup_install EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$stage_lib"
cp -R "$SOURCE_DIR/lib" "$SOURCE_DIR/bin" "$stage_lib/"
cp "$SOURCE_DIR/realm.sh" "$stage_lib/realm.sh"
cp "$SOURCE_DIR/THIRD_PARTY_NOTICES.md" "$stage_lib/"
printf '%s\n' RS_MANAGER_INSTALL_V1 >"$stage_lib/.rs-manager-install"
chmod +x "$stage_lib/bin/rs"
printf '#!/usr/bin/env bash\nRS_LIB_DIR=%q exec bash %q "$@"\n' "$LIB" "$LIB/bin/rs" >"$stage_rs"
printf '#!/usr/bin/env bash\nRS_LIB_DIR=%q exec bash %q singbox "${1:-menu}" "${@:2}"\n' "$LIB" "$LIB/bin/rs" >"$stage_sb"
chmod +x "$stage_rs" "$stage_sb"

bash -n "$stage_lib/bin/rs" "$stage_rs" "$stage_sb"
RS_LIB_DIR="$stage_lib" bash "$stage_lib/bin/rs" --help >/dev/null

if [[ -e $LIB ]]; then cp -a "$LIB" "$old_lib"; had_lib=1; fi
if [[ -e $BIN/rs ]]; then cp -a "$BIN/rs" "$old_rs"; had_rs=1; fi
if [[ -e $BIN/sb ]]; then cp -a "$BIN/sb" "$old_sb"; had_sb=1; fi
if [[ ${RS_TEST_MODE:-0} == 1 && ${RS_INSTALL_INJECT_FAILURE:-} == after-capture ]]; then false; fi
swapped=1
rm -rf "$LIB"; rm -f "$BIN/rs" "$BIN/sb"
mv "$stage_lib" "$LIB"
mv "$stage_rs" "$BIN/rs"
mv "$stage_sb" "$BIN/sb"

if [[ ${RS_TEST_MODE:-0} == 1 && ( ${RS_INSTALL_INJECT_FAILURE:-} == after-swap || ${RS_INSTALL_INJECT_FAILURE:-} == rollback-restore ) ]]; then false; fi
"$BIN/rs" --help >/dev/null

swapped=0
rm -rf "$old_lib" 2>/dev/null || true; rm -f "$old_rs" "$old_sb" 2>/dev/null || true
echo "Installed RS Manager: $BIN/rs (Sing-box shortcut: $BIN/sb)"
if [[ ${RS_LAUNCH:-0} == 1 && -t 0 ]]; then exec "$BIN/rs"; fi
