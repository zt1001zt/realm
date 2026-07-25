#!/usr/bin/env bash
: "${RS_SINGBOX_CONFIG:=/etc/sing-box/config.json}"
rs_sb_type_key(){ case "$1" in shadowsocks|ss) echo ss;; hysteria2|hy2) echo hy2;; tuic) echo tuic;; vless|reality) echo vless;; anytls) echo anytls;; *) return 1;; esac; }
rs_sb_password(){ if command -v openssl >/dev/null 2>&1; then openssl rand -base64 18 | tr -d '\r\n'; else rs_random_hex 18; fi; }
rs_sb_uuid(){ cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s-%s-%s-%s\n' "$(rs_random_hex 4)" "$(rs_random_hex 2)" "$(rs_random_hex 2)" "$(rs_random_hex 2)" "$(rs_random_hex 6)"; }
rs_sb_tag(){ local key; key=$(rs_sb_type_key "$1") || return 1; printf 'rs-%s-%s\n' "$key" "$(rs_random_hex 2)"; }
rs_sb_validate(){ jq -e '.inbounds and (.inbounds|type=="array")' "$1" >/dev/null || return 1; if command -v sing-box >/dev/null 2>&1 && [[ ${RS_TEST_MODE:-0} != 1 ]]; then sing-box check -c "$1" >/dev/null; fi; }
rs_sb_ensure(){ mkdir -p "$(dirname "$RS_SINGBOX_CONFIG")"; [[ -s $RS_SINGBOX_CONFIG ]] || printf '%s\n' '{"log":{"level":"info","timestamp":true},"inbounds":[],"outbounds":[{"type":"direct","tag":"direct-out"}]}' > "$RS_SINGBOX_CONFIG"; }
rs_sb_build(){
 local type=$1 tag=$2 port=$3 pass uuid private short; pass=$(rs_sb_password); uuid=$(rs_sb_uuid); private=$(rs_random_hex 16); short=$(rs_random_hex 4)
 case $(rs_sb_type_key "$type") in
 ss) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" '{type:"shadowsocks",tag:$t,listen:"::",listen_port:$p,method:"2022-blake3-aes-128-gcm",password:$x}' ;;
 hy2) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" '{type:"hysteria2",tag:$t,listen:"::",listen_port:$p,users:[{password:$x}],tls:{enabled:true,alpn:["h3"],certificate_path:"/etc/sing-box/certs/fullchain.pem",key_path:"/etc/sing-box/certs/privkey.pem"}}' ;;
 tuic) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" --arg u "$uuid" '{type:"tuic",tag:$t,listen:"::",listen_port:$p,users:[{uuid:$u,password:$x}],congestion_control:"bbr",tls:{enabled:true,alpn:["h3"],certificate_path:"/etc/sing-box/certs/fullchain.pem",key_path:"/etc/sing-box/certs/privkey.pem"}}' ;;
 vless) jq -cn --arg t "$tag" --argjson p "$port" --arg u "$uuid" --arg k "$private" --arg sid "$short" '{type:"vless",tag:$t,listen:"::",listen_port:$p,users:[{uuid:$u,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:"addons.mozilla.org",reality:{enabled:true,handshake:{server:"addons.mozilla.org",server_port:443},private_key:$k,short_id:[$sid]}}}' ;;
 anytls) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" --arg k "$private" --arg sid "$short" '{type:"anytls",tag:$t,listen:"::",listen_port:$p,users:[{name:"user",password:$x}],padding_scheme:[],tls:{enabled:true,server_name:"addons.mozilla.org",reality:{enabled:true,handshake:{server:"addons.mozilla.org",server_port:443},private_key:$k,short_id:[$sid]}}}' ;;
 esac
}
rs_sb_port_free(){ rs_sb_ensure; ! jq -e --argjson p "$1" '.inbounds[]?|select(.listen_port==$p)' "$RS_SINGBOX_CONFIG" >/dev/null && ! rs_port_is_used "$1"; }
rs_sb_add(){
 local type=$1 name=$2 port=$3 tag inbound tmp public_tmp public; rs_validate_port "$port" || return 1; rs_sb_port_free "$port" || return 1
 tag=$(rs_sb_tag "$type"); public_tmp=$(mktemp); RS_SB_PUBLIC_TMP=$public_tmp; export RS_SB_PUBLIC_TMP; inbound=$(rs_sb_build "$type" "$tag" "$port") || { rm -f "$public_tmp"; return 1; }; public=$(cat "$public_tmp"); rm -f "$public_tmp"; unset RS_SB_PUBLIC_TMP; tmp=$(mktemp)
 jq --argjson inbound "$inbound" '.inbounds=((.inbounds//[])+[$inbound])' "$RS_SINGBOX_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
 rs_sb_validate "$tmp" || { rm -f "$tmp"; return 1; }; rs_backup_create auto "$RS_SINGBOX_CONFIG" >/dev/null; rs_atomic_install "$tmp" "$RS_SINGBOX_CONFIG"; rm -f "$tmp"
 rs_state_init; local sf st; sf=$(rs_state_file); st="$sf.tmp-$$"; jq --arg t "$tag" --arg n "$name" --arg y "$(rs_sb_type_key "$type")" --arg pk "$public" '.singbox.instances[$t]={name:$n,type:$y,managed:true,public_key:$pk}' "$sf" > "$st" && mv "$st" "$sf"
 printf '%s\n' "$tag"
}
rs_sb_list(){ rs_sb_ensure; jq -r '.inbounds[]?|[.tag,.type,(.listen_port|tostring)]|@tsv' "$RS_SINGBOX_CONFIG"; }
rs_sb_edit(){ local tag=$1 field=$2 value=$3 tmp; tmp=$(mktemp); case $field in port|listen_port) rs_validate_port "$value" || return 1; jq --arg t "$tag" --argjson v "$value" '(.inbounds[]|select(.tag==$t).listen_port)=$v' "$RS_SINGBOX_CONFIG" > "$tmp";; sni|server_name) jq --arg t "$tag" --arg v "$value" '(.inbounds[]|select(.tag==$t).tls.server_name)=$v|(.inbounds[]|select(.tag==$t).tls.reality.handshake.server)=$v' "$RS_SINGBOX_CONFIG" > "$tmp";; *) return 1;; esac; rs_sb_validate "$tmp" && { rs_backup_create auto "$RS_SINGBOX_CONFIG" >/dev/null; rs_atomic_install "$tmp" "$RS_SINGBOX_CONFIG"; }; rm -f "$tmp"; }
rs_sb_delete(){ local tag=$1 tmp; tmp=$(mktemp); jq --arg t "$tag" '.inbounds|=map(select(.tag!=$t))' "$RS_SINGBOX_CONFIG" > "$tmp" && rs_sb_validate "$tmp" && { rs_backup_create auto "$RS_SINGBOX_CONFIG" >/dev/null; rs_atomic_install "$tmp" "$RS_SINGBOX_CONFIG"; }; rm -f "$tmp"; }
rs_sb_clone(){ local tag=$1 name=$2 port=$3 type; type=$(jq -r --arg t "$tag" '.inbounds[]|select(.tag==$t)|.type' "$RS_SINGBOX_CONFIG"); rs_sb_add "$type" "$name" "$port"; }
rs_sb_migrate(){ rs_sb_ensure; rs_state_init; local sf tmp tag type; sf=$(rs_state_file); while IFS=$'\t' read -r tag type; do [[ -n $tag ]] || continue; tmp="$sf.tmp-$$"; jq --arg t "$tag" --arg y "$type" '.singbox.instances[$t] //= {name:$t,type:$y,managed:false,legacy:true}' "$sf" > "$tmp" && mv "$tmp" "$sf"; done < <(jq -r '.inbounds[]?|select(.type=="shadowsocks" or .type=="hysteria2" or .type=="tuic" or .type=="vless" or .type=="anytls")|[.tag,.type]|@tsv' "$RS_SINGBOX_CONFIG"); }
rs_sb_urlencode(){ local value; value=$(tr -d '\r\n'); printf '%s' "$value" | jq -sRr @uri | tr -d '\r\n'; }
rs_sb_link(){
 local tag=$1 host=$2 row type port public sid password
 row=$(jq -c --arg t "$tag" '.inbounds[]|select(.tag==$t)' "$RS_SINGBOX_CONFIG") || return 1; [[ -n $row ]] || return 1
 type=$(jq -r .type <<< "$row"); port=$(jq -r .listen_port <<< "$row")
 case $type in
  shadowsocks) local method encoded; method=$(jq -r .method<<<"$row"); password=$(jq -r .password<<<"$row"); encoded=$(printf '%s' "$method:$password"|base64|tr -d '\n'); printf 'ss://%s@%s:%s#%s\n' "$encoded" "$host" "$port" "$tag" ;;
  hysteria2) password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'hy2://%s@%s:%s/?insecure=1#%s\n' "$password" "$host" "$port" "$tag" ;;
  tuic) password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'tuic://%s:%s@%s:%s/?congestion_control=bbr&insecure=1#%s\n' "$(jq -r '.users[0].uuid'<<<"$row")" "$password" "$host" "$port" "$tag" ;;
  vless) public=$(rs_state_get ".singbox.instances[\"$tag\"].public_key"); sid=$(jq -r '.tls.reality.short_id[0]'<<<"$row"); printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#%s\n' "$(jq -r '.users[0].uuid'<<<"$row")" "$host" "$port" "$(jq -r '.tls.server_name'<<<"$row")" "$public" "$sid" "$tag" ;;
  anytls) public=$(rs_state_get ".singbox.instances[\"$tag\"].public_key"); sid=$(jq -r '.tls.reality.short_id[0]'<<<"$row"); password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'anytls://%s@%s:%s/?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#%s\n' "$password" "$host" "$port" "$(jq -r '.tls.server_name'<<<"$row")" "$public" "$sid" "$tag" ;;
 esac
}