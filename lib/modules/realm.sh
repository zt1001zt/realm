#!/usr/bin/env bash
: "${RS_REALM_CONFIG:=/root/.realm/config.toml}"
rs_realm_ensure(){ mkdir -p "$(dirname "$RS_REALM_CONFIG")"; [[ -s $RS_REALM_CONFIG ]] || cat > "$RS_REALM_CONFIG" <<'EOF'
[network]
no_tcp = false
use_udp = true
EOF
}
rs_realm_validate(){ grep -q '^\[network\]' "$1" || return 1; local line p; while IFS= read -r line; do p=${line##*:}; p=${p%%\"*}; rs_validate_port "$p" || return 1; done < <(grep -E '^#? ?listen = ' "$1" | tr -d '\r'); }
rs_realm_listener_exists(){ rs_realm_ensure; grep -Eq "^#? ?listen = \"(\[::\]|0\.0\.0\.0):$1\"$" "$RS_REALM_CONFIG"; }
rs_realm_add(){ local id=$1 listen=$2 remote=$3 disabled=${4:-false} host port; rs_validate_name "$id" || return 1; rs_validate_port "$listen" || return 1; rs_realm_listener_exists "$listen" && return 1; host=${remote%:*}; port=${remote##*:}; rs_validate_host "${host#[}" || [[ $host == \[*\] ]] || return 1; rs_validate_port "$port" || return 1; rs_realm_ensure; rs_backup_create auto "$RS_REALM_CONFIG" >/dev/null; { printf '\n# rs:id=%s\n' "$id"; if [[ $disabled == true ]]; then printf '# rs:disabled\n# [[endpoints]]\n# listen = "[::]:%s"\n# remote = "%s"\n' "$listen" "$remote"; else printf '[[endpoints]]\nlisten = "[::]:%s"\nremote = "%s"\n' "$listen" "$remote"; fi; } >> "$RS_REALM_CONFIG"; rs_realm_validate "$RS_REALM_CONFIG"; }
rs_realm_get(){ local id=$1; awk -v marker="# rs:id=$id" '$0==marker{on=1;next} on{gsub(/^# /,""); if($0 ~ /^listen = /){split($0,a,"\""); l=a[2]} if($0 ~ /^remote = /){split($0,a,"\""); r=a[2]; print l "\t" r; exit}}' "$RS_REALM_CONFIG"; }
rs_realm_delete(){ local id=$1 tmp; rs_realm_ensure; tmp=$(mktemp); awk -v marker="# rs:id=$id" '$0==marker{skip=1;next} skip && /^$/{skip=0;next} !skip{print}' "$RS_REALM_CONFIG" > "$tmp"; rs_realm_validate "$tmp" && rs_atomic_install "$tmp" "$RS_REALM_CONFIG"; rm -f "$tmp"; }
rs_realm_edit(){ local id=$1 listen=$2 remote=$3; rs_realm_delete "$id" && rs_realm_add "$id" "$listen" "$remote"; }
rs_realm_toggle(){ local id=$1 state=$2 row listen remote; row=$(rs_realm_get "$id"); [[ -n $row ]] || return 1; listen=${row%%$'\t'*}; listen=${listen##*:}; remote=${row#*$'\t'}; rs_realm_delete "$id"; if [[ $state == disabled ]]; then rs_realm_add "$id" "$listen" "$remote" true; else rs_realm_add "$id" "$listen" "$remote" false; fi; }
rs_realm_add_range(){ local start=$1 end=$2 host=$3 remote=$4 p target; rs_validate_port "$start" && rs_validate_port "$end" && ((start<=end)) || return 1; for ((p=start;p<=end;p++)); do target=$((remote+p-start)); rs_realm_add "range-$p" "$p" "$host:$target" || return 1; done; }
rs_realm_list(){ rs_realm_ensure; awk '/^# rs:id=/{id=substr($0,9);d="enabled";next}/^# rs:disabled/{d="disabled"} /listen = /{gsub(/^# /,"");split($0,a,"\"");l=a[2]} /remote = /{gsub(/^# /,"");split($0,a,"\""); if(id!="") print id "\t" d "\t" l "\t" a[2]; id=""}' "$RS_REALM_CONFIG"; }
rs_realm_parse_link(){ local link=$1 authority hostport host port; authority=${link#*://}; authority=${authority#*@}; hostport=${authority%%/*}; if [[ $hostport == \[*\]:* ]]; then host=${hostport%%]*}; host=${host#[}; port=${hostport##*:}; else host=${hostport%:*}; port=${hostport##*:}; fi; rs_validate_host "$host" && rs_validate_port "$port" || return 1; printf '%s\t%s\n' "$host" "$port"; }
rs_realm_import_link(){ local link=$1 listen=$2 target; target=$(rs_realm_parse_link "$link") || return 1; rs_realm_add "link-$listen" "$listen" "${target//$'\t'/:}"; }
