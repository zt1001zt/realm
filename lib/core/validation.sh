#!/usr/bin/env bash
rs_validate_port(){ [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
rs_validate_host(){ local h=${1:-}; [[ -n $h && $h != *[[:space:]]* ]] || return 1; [[ $h =~ ^([A-Za-z0-9_][A-Za-z0-9_.-]*|[0-9A-Fa-f:]+)$ ]]; }
rs_validate_name(){ [[ ${1:-} =~ ^[A-Za-z0-9._-]{1,64}$ ]]; }
rs_port_is_used(){ local port=$1; command -v ss >/dev/null 2>&1 && ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[.:])${port}$"; }
rs_port_in_singbox(){ local port=$1 exclude=${2:-}; [[ -s ${RS_SINGBOX_CONFIG:-} ]] || return 1; jq -e --argjson p "$port" --arg x "$exclude" '.inbounds[]?|select(.listen_port==$p and (.tag//"")!=$x)' "$RS_SINGBOX_CONFIG" >/dev/null 2>&1; }
rs_port_in_realm(){ local port=$1 exclude=${2:-}; [[ -s ${RS_REALM_CONFIG:-} ]] || return 1; awk -v p="$port" -v x="$exclude" '
  /^# rs:id=/{pending=substr($0,9); next}
  /^#? ?\[\[endpoints\]\]/{id=pending; pending=""; next}
  /^\[[^[]/{id=""; pending=""}
  /^[# ]*listen = /{line=$0; gsub(/^# /,"",line); if((x=="" || id!=x) && line ~ ":" p "\"") found=1}
  END{exit !found}
' "$RS_REALM_CONFIG";
}
rs_port_available(){ local port=$1 sb_exclude=${2:-} realm_exclude=${3:-}; ! rs_port_in_singbox "$port" "$sb_exclude" && ! rs_port_in_realm "$port" "$realm_exclude" && ! rs_port_is_used "$port"; }
