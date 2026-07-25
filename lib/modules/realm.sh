#!/usr/bin/env bash
: "${RS_REALM_CONFIG:=/root/.realm/config.toml}"
rs_realm_ensure(){ mkdir -p "$(dirname "$RS_REALM_CONFIG")"; [[ -s $RS_REALM_CONFIG ]] || cat > "$RS_REALM_CONFIG" <<'EOF'
[network]
no_tcp = false
use_udp = true
EOF
}
rs_realm_toml_validate(){
 local file=$1 python candidate normalized output
 if [[ -n ${RS_PYTHON:-} ]]; then python=$RS_PYTHON; else
  for candidate in python3.13 python3.12 python3.11 python3 python; do command -v "$candidate" >/dev/null 2>&1 && { python=$candidate; break; }; done
 fi
 [[ -n ${python:-} ]] || { rs_die 'Python 3 with tomllib/tomli is required to validate Realm TOML'; return 1; }
 normalized=$("$python" -c 'import json,sys
try:
 import tomllib
except ImportError:
 try:
  import tomli as tomllib
 except ImportError:
  import toml
  data=toml.load(sys.argv[1])
 else:
  with open(sys.argv[1], "rb") as stream:
   data=tomllib.load(stream)
else:
 with open(sys.argv[1], "rb") as stream:
  data=tomllib.load(stream)
assert isinstance(data.get("network"), dict)
assert isinstance(data.get("endpoints", []), list)
for endpoint in data.get("endpoints", []):
 assert isinstance(endpoint, dict)
 assert isinstance(endpoint.get("listen"), str)
 assert isinstance(endpoint.get("remote"), str)
 endpoint["listen"]="127.0.0.1:0"
 endpoint["remote"]="127.0.0.1:9"
 network=endpoint.setdefault("network", {})
 assert isinstance(network, dict)
 network["no_tcp"]=True
 network["use_udp"]=False
data["network"]["no_tcp"]=True
data["network"]["use_udp"]=False
print(json.dumps(data))' "$file" 2>/dev/null) || return 1
 if command -v realm >/dev/null 2>&1 && [[ ${RS_TEST_MODE:-0} != 1 ]]; then
  output=$(REALM_CONF="$normalized" realm 2>&1) || return 1
  grep -q '^log:' <<<"$output" || return 1
 fi
}
rs_realm_validate(){ rs_realm_toml_validate "$1" || return 1; local line p; while IFS= read -r line; do line=${line#\# rs:off }; p=${line##*:}; p=${p%%\"*}; rs_validate_port "$p" || return 1; done < <(grep -E '^(# rs:off )?listen = ' "$1" | tr -d '\r'); }
rs_realm_post_apply(){ rs_service_reload_and_check realm; }
rs_realm_listener_exists_in(){ local file=$1 port=$2; grep -Eq "^(# rs:off )?listen = \"(\[::\]|0\.0\.0\.0):$port\"$" "$file"; }
rs_realm_listener_exists(){ rs_realm_ensure; rs_realm_listener_exists_in "$RS_REALM_CONFIG" "$1"; }
rs_realm_id_exists_in(){ grep -Fqx "# rs:id=$2" "$1"; }
rs_realm_validate_remote(){ local remote=$1 host port; if [[ $remote == \[*\]:* ]]; then host=${remote%%]*}; host=${host#[}; port=${remote##*:}; else host=${remote%:*}; port=${remote##*:}; fi; rs_validate_host "$host" && rs_validate_port "$port"; }
rs_realm_append_rule(){ local file=$1 id=$2 listen=$3 remote=$4 disabled=${5:-false} allow_system=${6:-false}; rs_validate_name "$id" && rs_validate_port "$listen" && rs_realm_validate_remote "$remote" || return 1; rs_realm_id_exists_in "$file" "$id" && return 1; rs_realm_listener_exists_in "$file" "$listen" && return 1; rs_port_in_singbox "$listen" && return 1; [[ $allow_system == true ]] || ! rs_port_is_used "$listen" || return 1; { printf '\n# rs:id=%s\n' "$id"; if [[ $disabled == true ]]; then printf '# rs:disabled\n# rs:off [[endpoints]]\n# rs:off listen = "[::]:%s"\n# rs:off remote = "%s"\n' "$listen" "$remote"; else printf '[[endpoints]]\nlisten = "[::]:%s"\nremote = "%s"\n' "$listen" "$remote"; fi; } >>"$file"; }
rs_realm_remove_rule(){ local input=$1 id=$2 output=$3 count; count=$(grep -Fxc "# rs:id=$id" "$input" || true); [[ $count == 1 ]] || return 1; awk -v marker="# rs:id=$id" '
 $0==marker{skip=1;table_seen=0;next}
 skip && /^# rs:id=/ {skip=0; print; next}
 skip {
   active=$0; sub(/^# rs:off /,"",active)
   if(active ~ /^\[\[/ || active ~ /^\[[^[]/) {
     if(active ~ /^\[\[endpoints\]\]/ && !table_seen){table_seen=1; next}
     if(active ~ /^\[\[?endpoints\./){next}
     if(table_seen){skip=0; print; next}
   }
   next
 }
 !skip{print}
' "$input" >"$output"; }
rs_realm_commit(){ local candidate=$1; rs_transaction_apply "$candidate" "$RS_REALM_CONFIG" rs_realm_validate rs_realm_post_apply >/dev/null; }
_rs_realm_add(){ local id=$1 listen=$2 remote=$3 disabled=${4:-false} tmp; rs_realm_ensure; tmp=$(mktemp); cp "$RS_REALM_CONFIG" "$tmp"; rs_realm_append_rule "$tmp" "$id" "$listen" "$remote" "$disabled" && rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"; }
rs_realm_add(){ rs_locked_call _rs_realm_add "$@"; }
rs_realm_get(){ local id=$1; awk -v marker="# rs:id=$id" '$0==marker{on=1;next} on{sub(/^# rs:off /,""); if($0 ~ /^listen = /){split($0,a,"\""); l=a[2]} if($0 ~ /^remote = /){split($0,a,"\""); r=a[2]; print l "\t" r; exit}}' "$RS_REALM_CONFIG"; }
_rs_realm_delete(){ local id=$1 tmp; rs_realm_ensure; tmp=$(mktemp); rs_realm_remove_rule "$RS_REALM_CONFIG" "$id" "$tmp" && rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"; }
rs_realm_delete(){ rs_locked_call _rs_realm_delete "$@"; }
_rs_realm_edit(){
 local id=$1 listen=$2 remote=$3 tmp row old_listen count; rs_realm_ensure
 rs_validate_port "$listen" && rs_realm_validate_remote "$remote" || return 1
 count=$(grep -Fxc "# rs:id=$id" "$RS_REALM_CONFIG" || true); [[ $count == 1 ]] || return 1
 row=$(rs_realm_get "$id"); [[ -n $row ]] || return 1; old_listen=${row%%$'\t'*}; old_listen=${old_listen##*:}
 rs_port_in_singbox "$listen" && return 1; rs_port_in_realm "$listen" "$id" && return 1; [[ $listen == "$old_listen" ]] || ! rs_port_is_used "$listen" || return 1
 tmp=$(mktemp)
 awk -v marker="# rs:id=$id" -v listen="$listen" -v remote="$remote" '
  $0==marker {inside=1; table_seen=0; print; next}
  inside && /^(# rs:off )?\[\[/ {if(table_seen){inside=0; print; next}; table_seen=1; print; next}
  inside && /^\[[^[]/ {inside=0; print; next}
  inside && /^$/ {inside=0; print; next}
  inside && /^(# rs:off )?listen = / {prefix=($0 ~ /^# rs:off / ? "# rs:off " : ""); print prefix "listen = \"[::]:" listen "\""; next}
  inside && /^(# rs:off )?remote = / {prefix=($0 ~ /^# rs:off / ? "# rs:off " : ""); print prefix "remote = \"" remote "\""; next}
  {print}
 ' "$RS_REALM_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
 rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"
}
rs_realm_edit(){ rs_locked_call _rs_realm_edit "$@"; }
_rs_realm_toggle(){
 local id=$1 state=$2 tmp count; [[ $state == disabled || $state == enabled ]] || return 1; rs_realm_ensure
 count=$(grep -Fxc "# rs:id=$id" "$RS_REALM_CONFIG" || true); [[ $count == 1 ]] || return 1; tmp=$(mktemp)
 awk -v marker="# rs:id=$id" -v state="$state" '
  $0==marker {inside=1; table_seen=0; print; if(state=="disabled") print "# rs:disabled"; next}
  inside && /^# rs:id=/ {inside=0; print; next}
  inside {
    active=$0; sub(/^# rs:off /,"",active)
    if(active ~ /^\[\[/ || active ~ /^\[[^[]/) {
      if(active ~ /^\[\[endpoints\]\]/ && !table_seen) table_seen=1
      else if(active ~ /^\[\[?endpoints\./) table_seen=1
      else if(table_seen){inside=0; print; next}
    }
    if($0=="# rs:disabled") next
    if(state=="disabled") {
      if($0 ~ /^# rs:off / || $0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) print
      else print "# rs:off " $0
      next
    }
    if($0 ~ /^# rs:off /) sub(/^# rs:off /,"")
    print; next
  }
  {print}
 ' "$RS_REALM_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
 rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"
}
rs_realm_toggle(){ rs_locked_call _rs_realm_toggle "$@"; }
_rs_realm_add_range(){ local start=$1 end=$2 host=$3 remote=$4 p target tmp; rs_validate_port "$start" && rs_validate_port "$end" && rs_validate_port "$remote" && rs_validate_host "$host" && ((10#$start<=10#$end)) || return 1; ((10#$remote+10#$end-10#$start<=65535)) || return 1; rs_realm_ensure; tmp=$(mktemp); cp "$RS_REALM_CONFIG" "$tmp"; for ((p=10#$start;p<=10#$end;p++)); do target=$((10#$remote+p-10#$start)); rs_realm_append_rule "$tmp" "range-$p" "$p" "$host:$target" || { rm -f "$tmp"; return 1; }; done; rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"; }
rs_realm_add_range(){ rs_locked_call _rs_realm_add_range "$@"; }
_rs_realm_migrate(){
 local tmp; rs_realm_ensure; tmp=$(mktemp)
 awk '
  NR==FNR {if($0 ~ /^# rs:id=/){id=substr($0,9); ids[id]=1}; next}
  /^# rs:id=/ {marked=1; print; next}
  /^# rs:disabled/ {print; next}
  /^(# rs:off )?\[\[endpoints\]\]/ {
    if(!marked){do{id="legacy-" ++n}while(ids[id]); ids[id]=1; print "# rs:id=" id}
    marked=0; print; next
  }
  {print}
 ' "$RS_REALM_CONFIG" "$RS_REALM_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
 if cmp -s "$tmp" "$RS_REALM_CONFIG"; then rm -f "$tmp"; return 0; fi
 rs_realm_commit "$tmp"; local rc=$?; rm -f "$tmp"; return "$rc"
}
rs_realm_migrate(){ rs_locked_call _rs_realm_migrate "$@"; }
rs_realm_list(){ rs_realm_ensure; awk '/^# rs:id=/{id=substr($0,9);d="enabled";next}/^# rs:disabled/{d="disabled"} /listen = /{sub(/^# rs:off /,"");split($0,a,"\"");l=a[2]} /remote = /{sub(/^# rs:off /,"");split($0,a,"\""); if(id!="") print id "\t" d "\t" l "\t" a[2]; id=""}' "$RS_REALM_CONFIG"; }
rs_realm_parse_link(){ local link=$1 authority hostport host port; authority=${link#*://}; authority=${authority#*@}; hostport=${authority%%/*}; if [[ $hostport == \[*\]:* ]]; then host=${hostport%%]*}; host=${host#[}; port=${hostport##*:}; else host=${hostport%:*}; port=${hostport##*:}; fi; rs_validate_host "$host" && rs_validate_port "$port" || return 1; printf '%s\t%s\n' "$host" "$port"; }
rs_realm_import_link(){ local link=$1 listen=$2 target; target=$(rs_realm_parse_link "$link") || return 1; rs_realm_add "link-$listen" "$listen" "${target//$'\t'/:}"; }
