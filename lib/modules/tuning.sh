#!/usr/bin/env bash
: "${RS_SYSCTL_FILE:=$(rs_path /etc/sysctl.d/99-rs-manager.conf)}"
rs_tune_buffer(){ case ${1:-standard} in low) echo 8388608;; standard) echo 16777216;; high) echo 33554432;; *) return 1;; esac; }
rs_tune_render(){ local profile=$1 b; b=$(rs_tune_buffer "$profile")||return 1; cat <<EOF
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
}
rs_tune_preview(){ local tmp; tmp=$(mktemp); rs_tune_render "$1">"$tmp"; if [[ -f $RS_SYSCTL_FILE ]]; then diff -u "$RS_SYSCTL_FILE" "$tmp"||true; else cat "$tmp"; fi; rm -f "$tmp"; }
rs_tune_apply(){ local profile=$1 tmp original; mkdir -p "$(dirname "$RS_SYSCTL_FILE")"; rs_state_init; original="$RS_STATE_DIR/sysctl.original"; [[ ! -e $RS_SYSCTL_FILE || -e $original ]] || cp -a "$RS_SYSCTL_FILE" "$original"; tmp=$(mktemp); rs_tune_render "$profile">"$tmp"; rs_atomic_install "$tmp" "$RS_SYSCTL_FILE"; rm -f "$tmp"; rs_state_set '.tuning.profile' "$profile"; if [[ ${RS_TEST_MODE:-0} != 1 ]]; then sysctl -p "$RS_SYSCTL_FILE"; local iface; iface=$(ip route show default|awk 'NR==1{print $5}'); [[ -z $iface ]]||tc qdisc replace dev "$iface" root fq 2>/dev/null||true; fi; }
rs_tune_restore(){ local original="$RS_STATE_DIR/sysctl.original"; if [[ -e $original ]]; then rs_atomic_install "$original" "$RS_SYSCTL_FILE"; rm -f "$original"; else rm -f "$RS_SYSCTL_FILE"; fi; [[ ${RS_TEST_MODE:-0} == 1 ]] || sysctl --system >/dev/null; }
rs_tune_realm(){ local extra; extra=$(rs_path /etc/sysctl.d/98-rs-realm.conf); mkdir -p "$(dirname "$extra")"; cat >"$extra" <<'EOF'
# Managed by RS Manager: Realm forwarding
net.netfilter.nf_conntrack_max = 262144
net.ipv4.tcp_keepalive_time = 300
EOF
 [[ ${RS_TEST_MODE:-0} == 1 ]]||sysctl -p "$extra"; }
rs_tune_status(){ printf 'kernel=%s\n' "$(uname -r)"; sysctl net.ipv4.tcp_available_congestion_control net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null||true; }
