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
rs_tune_preview(){ local tmp realm=false; tmp=$(mktemp); [[ $(rs_state_get '.tuning.realm' 2>/dev/null || true) == true ]] && realm=true; rs_tune_render "$1" "$realm">"$tmp"; if [[ -f $RS_SYSCTL_FILE ]]; then diff -u "$RS_SYSCTL_FILE" "$tmp"||true; else cat "$tmp"; fi; rm -f "$tmp"; }
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
  case $kind in sysctl) sysctl -w "$key=$value" >/dev/null 2>&1 || rc=1;; *) rc=1;; esac
 done <"$file"
 return "$rc"
}
rs_tune_check_support(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local available; available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
 if [[ " $available " != *' bbr '* ]]; then command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null || true; available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true); fi
 [[ " $available " == *' bbr '* ]] || { rs_die 'This kernel does not provide BBR'; return 1; }
}
rs_tune_prepare_original(){ local original="$RS_STATE_DIR/sysctl.original" absent="$RS_STATE_DIR/sysctl.original.absent"; rs_state_init; if [[ ! -e $original && ! -e $absent ]]; then if [[ -e $RS_SYSCTL_FILE ]]; then cp -a "$RS_SYSCTL_FILE" "$original"; else : >"$absent"; fi; fi; rs_tune_capture_runtime; }
rs_tune_post_apply(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local file=$1; sysctl -p "$file"
}
_rs_tune_apply(){
 local profile=$1 tmp realm=false; rs_tune_buffer "$profile" >/dev/null || return 1; rs_tune_check_support || return 1; rs_tune_prepare_original || return 1
 [[ $(rs_state_get '.tuning.realm' 2>/dev/null || true) == true ]] && realm=true
 tmp=$(mktemp); rs_tune_render "$profile" "$realm">"$tmp" || { rm -f "$tmp"; return 1; }
 if ! rs_transaction_apply "$tmp" "$RS_SYSCTL_FILE" rs_tune_validate rs_tune_post_apply >/dev/null; then rm -f "$tmp"; rs_tune_restore_runtime; return 1; fi
 rm -f "$tmp"; rs_state_set '.tuning.profile' "$profile"
}
rs_tune_apply(){ rs_locked_call _rs_tune_apply "$@"; }
_rs_tune_realm(){
 local profile tmp; profile=$(rs_state_get '.tuning.profile' 2>/dev/null || true); [[ -n $profile ]] || profile=realm; [[ $profile == realm ]] || rs_tune_check_support || return 1; rs_tune_prepare_original || return 1
 tmp=$(mktemp); rs_tune_render "$profile" true >"$tmp" || { rm -f "$tmp"; return 1; }
 if ! rs_transaction_apply "$tmp" "$RS_SYSCTL_FILE" rs_tune_validate rs_tune_post_apply >/dev/null; then rm -f "$tmp"; rs_tune_restore_runtime; return 1; fi
 rm -f "$tmp"; rs_state_set_json '.tuning.realm' true
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
