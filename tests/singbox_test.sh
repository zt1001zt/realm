#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
DIR=$(cd "$(dirname "$0")/.." && pwd); export PATH="$DIR/../tools:$PATH"
source "$DIR/tests/test_helper.sh"; for f in "$DIR"/lib/core/*.sh; do source "$f"; done; source "$DIR/lib/modules/singbox.sh"
make_root; trap cleanup_root EXIT
export RS_STATE_DIR="$RS_ROOT/etc/rs-manager" RS_BACKUP_DIR="$RS_ROOT/backups" RS_SINGBOX_CONFIG="$RS_ROOT/etc/sing-box/config.json" RS_SINGBOX_CERT_DIR="$RS_ROOT/etc/sing-box/certs" RS_REALM_CONFIG="$RS_ROOT/root/.realm/config.toml"
mkdir -p "$RS_ROOT/test-bin" "$(dirname "$RS_REALM_CONFIG")"
missing_output=''; missing_rc=0
missing_output=$( (
  export PATH=/usr/bin:/bin
  source "$DIR/lib/core/common.sh"
  source "$DIR/lib/modules/singbox.sh"
  rs_sb_reality_keypair
 ) 2>&1 ) || missing_rc=$?
assert_eq "$missing_rc" 1
assert_true grep -Fq 'sing-box is not installed; run: rs service install sing-box' <<<"$missing_output"
cat > "$RS_ROOT/test-bin/sing-box" <<'EOF'
#!/usr/bin/env sh
if [ "$1 $2" = "generate reality-keypair" ]; then
  printf '%s\n' 'PrivateKey: TEST_PRIVATE_KEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' 'PublicKey: TEST_PUBLIC_KEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'
  exit 0
fi
if [ "$1" = "check" ] || [ "$1" = "version" ]; then exit 0; fi
exit 1
EOF
chmod +x "$RS_ROOT/test-bin/sing-box"
export PATH="$RS_ROOT/test-bin:$PATH"
cat > "$RS_REALM_CONFIG" <<'EOF'
[network]
no_tcp = false
use_udp = true

[[endpoints]]
listen = "[::]:16000"
remote = "target.example.com:26000"
EOF
mkdir -p "$(dirname "$RS_SINGBOX_CONFIG")"; cp "$DIR/tests/fixtures/singbox-existing.json" "$RS_SINGBOX_CONFIG"
jq '.inbounds += [{type:"vless",tag:"legacy-reality",listen:"::",listen_port:12500,users:[{uuid:"11111111-1111-4111-8111-111111111111",flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:"addons.mozilla.org",reality:{enabled:true,handshake:{server:"addons.mozilla.org",server_port:443},private_key:"6I-bblbPzkMuT-igbWKaOJI5c22HyGlAwXY4PwnST28",short_id:["01234567"]}}}]' "$RS_SINGBOX_CONFIG" >"$RS_ROOT/sb-with-legacy.json"; mv "$RS_ROOT/sb-with-legacy.json" "$RS_SINGBOX_CONFIG"
rs_sb_migrate
assert_eq "$(rs_state_get '.singbox.instances["legacy-ss"].type')" shadowsocks
assert_eq "$(rs_state_get '.singbox.instances["legacy-reality"].public_key')" rVvTl7AF2U722w9YH9XkJs80U87Mt1fOBDTtg-bFh3E
assert_true grep -q 'pbk=rVvTl7AF2U722w9YH9XkJs80U87Mt1fOBDTtg-bFh3E' <<<"$(rs_sb_link legacy-reality example.com)"
hy=$(rs_sb_add hysteria2 hy-main 13000); vl=$(rs_sb_add vless reality-main 14000); ss2=$(rs_sb_add shadowsocks ss-two 15000)
assert_true test -s "$RS_SINGBOX_CERT_DIR/fullchain.pem"
assert_true test -s "$RS_SINGBOX_CERT_DIR/privkey.pem"
assert_eq "$(jq '.inbounds|length' "$RS_SINGBOX_CONFIG")" 5
assert_eq "$(jq -r '.dns.servers[0].tag' "$RS_SINGBOX_CONFIG")" custom
assert_eq "$(jq -r '.experimental.cache_file.enabled' "$RS_SINGBOX_CONFIG")" true
assert_true test "$hy" != "$vl"
assert_eq "$(jq -r --arg t "$vl" '.inbounds[]|select(.tag==$t)|.tls.reality.private_key' "$RS_SINGBOX_CONFIG")" TEST_PRIVATE_KEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456
assert_eq "$(rs_state_get ".singbox.instances[\"$vl\"].public_key")" TEST_PUBLIC_KEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456
assert_false rs_sb_add shadowsocks duplicate-port 15000
assert_false rs_sb_add shadowsocks realm-port 16000
rs_sb_delete "$ss2"
assert_eq "$(jq --arg t "$ss2" '[.inbounds[]|select(.tag==$t)]|length' "$RS_SINGBOX_CONFIG")" 0
assert_eq "$(rs_state_get ".singbox.instances[\"$ss2\"].managed")" ''
assert_false rs_sb_delete does-not-exist
assert_false rs_sb_edit does-not-exist port 16001
assert_eq "$(jq -r '.inbounds[]|select(.tag=="legacy-ss")|.password' "$RS_SINGBOX_CONFIG")" legacy-pass
vlink=$(rs_sb_link "$vl" example.com)
assert_true grep -q 'pbk=TEST_PUBLIC_KEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456.*sid=' <<< "$vlink"
saved_public=$(rs_state_get ".singbox.instances[\"$vl\"].public_key")
rs_state_set ".singbox.instances[\"$vl\"].public_key" ''
assert_false rs_sb_link "$vl" example.com
rs_state_set ".singbox.instances[\"$vl\"].public_key" "$saved_public"
hlink=$(rs_sb_link "$hy" example.com)
assert_false grep -q '%0A\|%0D' <<< "$hlink"
cat >"$RS_ROOT/etc/os-release" <<'EOF'
ID=alpine
EOF
mkdir -p "$RS_ROOT/etc/init.d"
printf '#!/sbin/openrc-run\n' >"$RS_ROOT/etc/init.d/sing-box"; chmod +x "$RS_ROOT/etc/init.d/sing-box"
cat >"$RS_ROOT/test-bin/rc-service" <<EOF
#!/usr/bin/env sh
printf '%s\n' "\$*" >>'$RS_ROOT/rc.log'
EOF
chmod +x "$RS_ROOT/test-bin/rc-service"
rs_sb_password(){ [[ -d $RS_LOCK_DIR ]] && : >"$RS_ROOT/lock-seen"; printf '%s\n' test-password; }
RS_TEST_MODE=0 rs_sb_add shadowsocks alpine-live 18000 >/dev/null
assert_true grep -q '^sing-box restart$' "$RS_ROOT/rc.log"
assert_true test -f "$RS_ROOT/lock-seen"
finish
