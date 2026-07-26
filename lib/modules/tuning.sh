#!/usr/bin/env bash
: "${RS_SYSCTL_FILE:=$(rs_path /etc/sysctl.d/99-rs-manager.conf)}"
rs_tune_buffer(){ case ${1:-standard} in low) echo 8388608;; standard) echo 16777216;; high) echo 33554432;; *) return 1;; esac; }
rs_tune_render(){
 local profile=$1 include_realm=${2:-false} b
 if [[ $profile != realm ]]; then
  b=$(rs_tune_buffer "$profile")||return 1
  cat <<EOF
# Managed by RS Manager - profile: $profile
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = $b
net.core.wmem_max = $b
net.ipv4.tcp_rmem = 4096 87380 $b
net.ipv4.tcp_wmem = 4096 65536 $b
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
EOF
 else
  printf '%s\n' '# Managed by RS Manager - profile: realm'
  include_realm=true
 fi
 if [[ $include_realm == true ]]; then
  cat <<'EOF'
# Realm forwarding additions managed by RS Manager
net.netfilter.nf_conntrack_max = 262144
net.ipv4.tcp_keepalive_time = 300
EOF
 fi
}
rs_tune_validate(){ grep -q '^# Managed by RS Manager' "$1" && ! grep -Ev '^(#.*|$|net\.(core|ipv4|netfilter)\.[A-Za-z0-9_.]+ = [0-9A-Za-z ]+)$' "$1" | grep -q .; }
rs_tune_key_supported(){ [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0; sysctl -n "$1" >/dev/null 2>&1; }
rs_tune_filter_supported(){
 local template=$1 candidate=$2 skipped=$3 line key
 : >"$candidate"; : >"$skipped"
 while IFS= read -r line || [[ -n $line ]]; do
  case $line in
   ''|'#'*)printf '%s\n' "$line" >>"$candidate";;
   *=*)
    key=${line%%=*}; key=${key//[[:space:]]/}
    if rs_tune_key_supported "$key"; then printf '%s\n' "$line" >>"$candidate"; else printf '%s\n' "$key" >>"$skipped"; fi
    ;;
  esac
 done <"$template"
}
rs_tune_candidate(){
 local profile=$1 candidate=$2 skipped=$3 include_realm=${4:-auto} template realm=false
 template=$(mktemp) || return 1
 if [[ $include_realm == auto ]]; then [[ $(rs_state_get '.tuning.realm' 2>/dev/null || true) == true ]] && realm=true; else realm=$include_realm; fi
 if ! rs_tune_render "$profile" "$realm" >"$template" || ! rs_tune_filter_supported "$template" "$candidate" "$skipped"; then rm -f "$template"; return 1; fi
 rm -f "$template"
}
rs_tune_preview(){
 local tmp skipped; tmp=$(mktemp); skipped=$(mktemp)
 rs_tune_candidate "$1" "$tmp" "$skipped" || { rm -f "$tmp" "$skipped"; return 1; }
 if [[ -f $RS_SYSCTL_FILE ]]; then diff -u "$RS_SYSCTL_FILE" "$tmp"||true; else cat "$tmp"; fi
 if [[ -s $skipped ]]; then printf '%s\n' '系统不支持，已跳过：'; sed 's/^/  - /' "$skipped"; fi
 rm -f "$tmp" "$skipped"
}
rs_tune_runtime_file(){ printf '%s/sysctl.runtime\n' "$RS_STATE_DIR"; }
rs_tune_keys(){ cat <<'EOF'
net.core.default_qdisc
net.ipv4.tcp_congestion_control
net.core.rmem_max
net.core.wmem_max
net.ipv4.tcp_rmem
net.ipv4.tcp_wmem
net.core.somaxconn
net.ipv4.tcp_max_syn_backlog
net.ipv4.tcp_mtu_probing
net.ipv4.tcp_fastopen
net.ipv4.tcp_keepalive_time
net.ipv4.tcp_keepalive_intvl
net.ipv4.tcp_keepalive_probes
net.ipv4.tcp_syncookies
net.netfilter.nf_conntrack_max
EOF
}
rs_tune_capture_runtime(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 rs_state_init; local file key value; file=$(rs_tune_runtime_file); [[ -e $file ]] && return 0
 : >"$file"; while IFS= read -r key; do value=$(sysctl -n "$key" 2>/dev/null) || continue; printf 'sysctl\t%s\t%s\n' "$key" "$value" >>"$file"; done < <(rs_tune_keys)
 chmod 600 "$file"
}
rs_tune_restore_runtime(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local file kind key value rc=0; file=$(rs_tune_runtime_file); [[ -s $file ]] || return 0
 while IFS=$'\t' read -r kind key value; do
  case $kind in
   sysctl)if ! sysctl -w "$key=$value" >/dev/null 2>&1; then rs_warn "无法恢复 sysctl：$key"; rc=1; fi;;
   *)rs_warn "无法识别的运行时恢复项：$kind";rc=1;;
  esac
 done <"$file"
 return "$rc"
}
rs_tune_check_support(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local available current
 rs_tune_key_supported net.ipv4.tcp_available_congestion_control || { rs_die '当前环境未提供 BBR 拥塞控制能力'; return 1; }
 rs_tune_key_supported net.ipv4.tcp_congestion_control || { rs_die '当前环境不允许读取 TCP 拥塞控制参数'; return 1; }
 available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
 if [[ " $available " != *' bbr '* ]]; then command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null || true; available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true); fi
 [[ " $available " == *' bbr '* ]] || { rs_die '当前内核不提供 BBR'; return 1; }
 current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) || return 1
 sysctl -w "net.ipv4.tcp_congestion_control=$current" >/dev/null 2>&1 || { rs_die '当前环境不允许写入 TCP 拥塞控制参数'; return 1; }
}
rs_tune_prepare_original(){ local original="$RS_STATE_DIR/sysctl.original" absent="$RS_STATE_DIR/sysctl.original.absent"; rs_state_init; if [[ ! -e $original && ! -e $absent ]]; then if [[ -e $RS_SYSCTL_FILE ]]; then cp -a "$RS_SYSCTL_FILE" "$original"; else : >"$absent"; fi; fi; rs_tune_capture_runtime; }
rs_tune_post_apply(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local file=$1 line key value
 [[ -f $file ]] || return 0
 while IFS= read -r line || [[ -n $line ]]; do
  case $line in ''|'#'*)continue;;esac
  key=${line%%=*}; value=${line#*=}; key=${key//[[:space:]]/}
  value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
  sysctl -w "$key=$value" >/dev/null || return 1
 done <"$file"
}
_rs_tune_apply(){
 local profile=$1 tmp skipped key; rs_tune_buffer "$profile" >/dev/null || return 1; rs_tune_check_support || return 1; rs_tune_prepare_original || return 1
 tmp=$(mktemp); skipped=$(mktemp); rs_tune_candidate "$profile" "$tmp" "$skipped" || { rm -f "$tmp" "$skipped"; return 1; }
 while IFS= read -r key; do [[ -n $key ]] && rs_warn "系统不支持，已跳过：$key"; done <"$skipped"
 if ! rs_transaction_apply "$tmp" "$RS_SYSCTL_FILE" rs_tune_validate rs_tune_post_apply >/dev/null; then rm -f "$tmp" "$skipped"; rs_tune_restore_runtime; return 1; fi
 rm -f "$tmp" "$skipped"; rs_state_set '.tuning.profile' "$profile"
}
rs_tune_apply(){ rs_locked_call _rs_tune_apply "$@"; }
_rs_tune_realm(){
 local profile tmp skipped key; profile=$(rs_state_get '.tuning.profile' 2>/dev/null || true); [[ -n $profile ]] || profile=realm; [[ $profile == realm ]] || rs_tune_check_support || return 1; rs_tune_prepare_original || return 1
 tmp=$(mktemp); skipped=$(mktemp); rs_tune_candidate "$profile" "$tmp" "$skipped" true || { rm -f "$tmp" "$skipped"; return 1; }
 while IFS= read -r key; do [[ -n $key ]] && rs_warn "系统不支持，已跳过：$key"; done <"$skipped"
 if ! rs_transaction_apply "$tmp" "$RS_SYSCTL_FILE" rs_tune_validate rs_tune_post_apply >/dev/null; then rm -f "$tmp" "$skipped"; rs_tune_restore_runtime; return 1; fi
 rm -f "$tmp" "$skipped"; rs_state_set_json '.tuning.realm' true
}
rs_tune_realm(){ rs_locked_call _rs_tune_realm "$@"; }
_rs_tune_restore(){
 local original="$RS_STATE_DIR/sysctl.original" absent="$RS_STATE_DIR/sysctl.original.absent" legacy; legacy=$(rs_path /etc/sysctl.d/98-rs-realm.conf)
 if [[ -e $original ]]; then rs_atomic_install "$original" "$RS_SYSCTL_FILE" || return 1; else rm -f "$RS_SYSCTL_FILE" || return 1; fi
 if [[ ${RS_TEST_MODE:-0} != 1 ]]; then rs_tune_restore_runtime || return 1; fi
 rs_state_set_json '.tuning' '{}' || return 1
 if [[ -f $legacy ]] && grep -q '^# Managed by RS Manager' "$legacy"; then rm -f "$legacy" || return 1; fi
 rm -f "$original" "$absent" "$(rs_tune_runtime_file)"
}
rs_tune_restore(){ rs_locked_call _rs_tune_restore "$@"; }
rs_tune_status(){ printf 'kernel=%s\n' "$(uname -r)"; sysctl net.ipv4.tcp_available_congestion_control net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null||true; }
rs_tune_smart_preview(){
 printf '%s\n' '智能检测结果：'
 rs_tune_status
 printf 'memory_kb=%s\n' "$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
 printf 'nofile=%s\n' "$(ulimit -n)"
 rs_tune_check_support || return 1
 printf '%s\n' '将应用以下 BBR/TCP 参数：'
 rs_tune_preview standard
}
