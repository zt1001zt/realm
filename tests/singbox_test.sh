#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/singbox.sh"
make_root; trap cleanup_root EXIT
export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_BACKUP_DIR="$RS_ROOT/backups" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json"
mkdir -p "$(dirname "$RS_SINGBOX_CONFIG")"; cp "$DIR/tests/fixtures/singbox-existing.json" "$RS_SINGBOX_CONFIG"
rs_sb_migrate
assert_eq "$(rs_state_get '.singbox.instances["legacy-ss"].type')" shadowsocks
hy=$(rs_sb_add hysteria2 hy-main 13000); vl=$(rs_sb_add vless reality-main 14000); ss2=$(rs_sb_add shadowsocks ss-two 15000)
assert_eq "$(jq '.inbounds|length' "$RS_SINGBOX_CONFIG")" 4
assert_eq "$(jq -r '.dns.servers[0].tag' "$RS_SINGBOX_CONFIG")" custom
assert_eq "$(jq -r '.experimental.cache_file.enabled' "$RS_SINGBOX_CONFIG")" true
assert_true test "$hy" != "$vl"
rs_sb_delete "$ss2"
assert_eq "$(jq --arg t "$ss2" '[.inbounds[]|select(.tag==$t)]|length' "$RS_SINGBOX_CONFIG")" 0
assert_eq "$(jq -r '.inbounds[]|select(.tag=="legacy-ss")|.password' "$RS_SINGBOX_CONFIG")" legacy-pass
vlink=$(rs_sb_link "$vl" example.com)
assert_true grep -q 'pbk=.*sid=' <<< "$vlink"
hlink=$(rs_sb_link "$hy" example.com)
assert_false grep -q '%0A\|%0D' <<< "$hlink"
finish
