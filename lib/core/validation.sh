#!/usr/bin/env bash
rs_validate_port(){ [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
rs_validate_host(){ local h=${1:-}; [[ -n $h && $h != *[[:space:]]* ]] || return 1; [[ $h =~ ^([A-Za-z0-9_][A-Za-z0-9_.-]*|[0-9A-Fa-f:]+)$ ]]; }
rs_validate_name(){ [[ ${1:-} =~ ^[A-Za-z0-9._-]{1,64}$ ]]; }
rs_port_is_used(){ local port=$1; command -v ss >/dev/null 2>&1 && ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[.:])${port}$"; }
