#!/usr/bin/env bash
: "${RS_ROOT:=}"
rs_path(){ printf '%s%s\n' "$RS_ROOT" "$1"; }
rs_die(){ printf 'ERROR: %s\n' "$*" >&2; return 1; }
rs_info(){ printf '[INFO] %s\n' "$*"; }
rs_warn(){ printf '[WARN] %s\n' "$*" >&2; }
rs_require_root(){ [[ ${RS_TEST_MODE:-0} == 1 || ${EUID:-1} -eq 0 ]] || rs_die 'Run as root'; }
rs_random_hex(){ local bytes=${1:-3}; if command -v openssl >/dev/null 2>&1; then openssl rand -hex "$bytes"; else od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'; fi; }
