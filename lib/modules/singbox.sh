#!/usr/bin/env bash
: "${RS_SINGBOX_CONFIG:=/etc/sing-box/config.json}"
: "${RS_SINGBOX_CERT_DIR:=}"
rs_sb_type_key(){ case "$1" in shadowsocks|ss) echo ss;; hysteria2|hy2) echo hy2;; tuic) echo tuic;; vless|reality) echo vless;; anytls) echo anytls;; *) return 1;; esac; }
rs_sb_password(){ if command -v openssl >/dev/null 2>&1; then openssl rand -base64 18 | tr -d '\r\n'; else rs_random_hex 18; fi; }
rs_sb_uuid(){ cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s-%s-%s-%s\n' "$(rs_random_hex 4)" "$(rs_random_hex 2)" "$(rs_random_hex 2)" "$(rs_random_hex 2)" "$(rs_random_hex 6)"; }
rs_sb_tag(){ local key tag i=0; key=$(rs_sb_type_key "$1") || return 1; while ((i<100)); do tag="rs-$key-$(rs_random_hex 3)"; if [[ ! -s $RS_SINGBOX_CONFIG ]] || ! jq -e --arg t "$tag" '.inbounds[]?|select(.tag==$t)' "$RS_SINGBOX_CONFIG" >/dev/null; then printf '%s\n' "$tag"; return 0; fi; i=$((i+1)); done; return 1; }
rs_sb_reality_keypair(){
 local output private public
 command -v sing-box >/dev/null 2>&1 || { rs_die 'sing-box is required to generate Reality keys'; return 1; }
 output=$(sing-box generate reality-keypair 2>/dev/null) || return 1
 private=$(awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' <<<"$output")
 public=$(awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}' <<<"$output")
 [[ $private =~ ^[A-Za-z0-9_-]{32,64}$ && $public =~ ^[A-Za-z0-9_-]{32,64}$ ]] || { rs_die 'Invalid Reality keypair output'; return 1; }
 printf '%s\t%s\n' "$private" "$public"
}
rs_sb_reality_public_from_private(){
 local private=$1 encoded work public
 [[ $private =~ ^[A-Za-z0-9_-]{43,44}$ ]] || return 1
 command -v openssl >/dev/null 2>&1 || return 1
 work=$(mktemp -d) || return 1; chmod 700 "$work"
 encoded=$(printf '%s' "$private" | tr '_-' '/+')
 case $((${#encoded}%4)) in 2) encoded+='==';; 3) encoded+='=';; esac
 printf '\060\056\002\001\000\060\005\006\003\053\145\156\004\042\004\040' >"$work/private.der"
 if ! printf '%s' "$encoded" | openssl base64 -d -A >>"$work/private.der" || [[ $(wc -c <"$work/private.der" | tr -d ' ') != 48 ]]; then rm -rf "$work"; return 1; fi
 if ! openssl pkey -inform DER -in "$work/private.der" -pubout -outform DER -out "$work/public.der" >/dev/null 2>&1; then rm -rf "$work"; return 1; fi
 public=$(dd if="$work/public.der" bs=1 skip=12 2>/dev/null | openssl base64 -A | tr '+/' '-_' | tr -d '='); rm -rf "$work"
 [[ $public =~ ^[A-Za-z0-9_-]{43,44}$ ]] || return 1
 printf '%s\n' "$public"
}
rs_sb_ensure_certificate(){
 local dir cert key cert_tmp key_tmp
 dir=${RS_SINGBOX_CERT_DIR:-$(rs_path /etc/sing-box/certs)}; RS_SINGBOX_CERT_DIR=$dir; cert="$dir/fullchain.pem"; key="$dir/privkey.pem"
 [[ -s $cert && -s $key ]] && return 0
 [[ ! -e $cert && ! -e $key ]] || { rs_die 'Certificate pair is incomplete; refusing to overwrite it'; return 1; }
 command -v openssl >/dev/null 2>&1 || { rs_die 'openssl is required to create a TLS certificate'; return 1; }
 mkdir -p "$dir"; cert_tmp=$(mktemp "$dir/.cert.XXXXXX"); key_tmp=$(mktemp "$dir/.key.XXXXXX")
 if ! openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 -subj '/CN=www.cloudflare.com' -keyout "$key_tmp" -out "$cert_tmp" >/dev/null 2>&1; then rm -f "$cert_tmp" "$key_tmp"; return 1; fi
 chmod 600 "$key_tmp"; chmod 644 "$cert_tmp"; mv "$key_tmp" "$key"; mv "$cert_tmp" "$cert"
}
rs_sb_validate(){ jq -e '.inbounds and (.inbounds|type=="array")' "$1" >/dev/null || return 1; if command -v sing-box >/dev/null 2>&1 && [[ ${RS_TEST_MODE:-0} != 1 ]]; then sing-box check -c "$1" >/dev/null; fi; }
rs_sb_post_apply(){ rs_service_reload_and_check sing-box; }
rs_sb_ensure(){ mkdir -p "$(dirname "$RS_SINGBOX_CONFIG")"; [[ -s $RS_SINGBOX_CONFIG ]] || printf '%s\n' '{"log":{"level":"info","timestamp":true},"inbounds":[],"outbounds":[{"type":"direct","tag":"direct-out"}]}' > "$RS_SINGBOX_CONFIG"; }
rs_sb_build(){
 local type=$1 tag=$2 port=$3 pass uuid private='' public='' short cert_dir cert key; pass=$(rs_sb_password); uuid=$(rs_sb_uuid); short=$(rs_random_hex 4); cert_dir=${RS_SINGBOX_CERT_DIR:-$(rs_path /etc/sing-box/certs)}; cert="$cert_dir/fullchain.pem"; key="$cert_dir/privkey.pem"
 case $(rs_sb_type_key "$type") in
 ss) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" '{type:"shadowsocks",tag:$t,listen:"::",listen_port:$p,method:"2022-blake3-aes-128-gcm",password:$x}' ;;
 hy2) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" --arg c "$cert" --arg k "$key" '{type:"hysteria2",tag:$t,listen:"::",listen_port:$p,users:[{password:$x}],tls:{enabled:true,alpn:["h3"],certificate_path:$c,key_path:$k}}' ;;
 tuic) jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" --arg u "$uuid" --arg c "$cert" --arg k "$key" '{type:"tuic",tag:$t,listen:"::",listen_port:$p,users:[{uuid:$u,password:$x}],congestion_control:"bbr",tls:{enabled:true,alpn:["h3"],certificate_path:$c,key_path:$k}}' ;;
 vless) IFS=$'\t' read -r private public < <(rs_sb_reality_keypair) || return 1; [[ -z ${RS_SB_PUBLIC_TMP:-} ]] || printf '%s' "$public" >"$RS_SB_PUBLIC_TMP"; jq -cn --arg t "$tag" --argjson p "$port" --arg u "$uuid" --arg k "$private" --arg sid "$short" '{type:"vless",tag:$t,listen:"::",listen_port:$p,users:[{uuid:$u,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:"addons.mozilla.org",reality:{enabled:true,handshake:{server:"addons.mozilla.org",server_port:443},private_key:$k,short_id:[$sid]}}}' ;;
 anytls) IFS=$'\t' read -r private public < <(rs_sb_reality_keypair) || return 1; [[ -z ${RS_SB_PUBLIC_TMP:-} ]] || printf '%s' "$public" >"$RS_SB_PUBLIC_TMP"; jq -cn --arg t "$tag" --argjson p "$port" --arg x "$pass" --arg k "$private" --arg sid "$short" '{type:"anytls",tag:$t,listen:"::",listen_port:$p,users:[{name:"user",password:$x}],padding_scheme:[],tls:{enabled:true,server_name:"addons.mozilla.org",reality:{enabled:true,handshake:{server:"addons.mozilla.org",server_port:443},private_key:$k,short_id:[$sid]}}}' ;;
 esac
}
rs_sb_port_free(){ rs_sb_ensure; rs_port_available "$1" "${2:-}"; }
_rs_sb_add(){
 local type=$1 name=$2 port=$3 tag inbound tmp public_tmp public key; key=$(rs_sb_type_key "$type") || return 1; rs_validate_name "$name" || return 1; rs_validate_port "$port" || return 1; rs_sb_port_free "$port" || return 1; if [[ $key == hy2 || $key == tuic ]]; then rs_sb_ensure_certificate || return 1; fi
 tag=$(rs_sb_tag "$type"); public_tmp=$(mktemp); RS_SB_PUBLIC_TMP=$public_tmp; export RS_SB_PUBLIC_TMP; inbound=$(rs_sb_build "$type" "$tag" "$port") || { rm -f "$public_tmp"; return 1; }; public=$(cat "$public_tmp"); rm -f "$public_tmp"; unset RS_SB_PUBLIC_TMP; tmp=$(mktemp)
 jq --argjson inbound "$inbound" '.inbounds=((.inbounds//[])+[$inbound])' "$RS_SINGBOX_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
 rs_state_init; local sf st; sf=$(rs_state_file); st=$(mktemp); jq --arg t "$tag" --arg n "$name" --arg y "$(rs_sb_type_key "$type")" --arg pk "$public" '.singbox.instances[$t]={name:$n,type:$y,managed:true,public_key:$pk}' "$sf" > "$st" && chmod 600 "$st" || { rm -f "$tmp" "$st"; return 1; }
 rs_transaction_apply_pair "$tmp" "$RS_SINGBOX_CONFIG" "$st" "$sf" rs_sb_validate rs_sb_post_apply || { rm -f "$tmp" "$st"; return 1; }; rm -f "$tmp" "$st"
 printf '%s\n' "$tag"
}
rs_sb_add(){ rs_locked_call _rs_sb_add "$@"; }
rs_sb_list(){ rs_sb_ensure; jq -r '.inbounds[]?|[.tag,.type,(.listen_port|tostring)]|@tsv' "$RS_SINGBOX_CONFIG"; }
_rs_sb_edit(){ local tag=$1 field=$2 value=$3 tmp count; count=$(jq --arg t "$tag" '[.inbounds[]?|select(.tag==$t)]|length' "$RS_SINGBOX_CONFIG"); [[ $count == 1 ]] || return 1; tmp=$(mktemp); case $field in port|listen_port) rs_validate_port "$value" || return 1; rs_sb_port_free "$value" "$tag" || return 1; jq --arg t "$tag" --argjson v "$value" '(.inbounds[]|select(.tag==$t).listen_port)=$v' "$RS_SINGBOX_CONFIG" > "$tmp";; sni|server_name) jq --arg t "$tag" --arg v "$value" '(.inbounds[]|select(.tag==$t).tls.server_name)=$v|(.inbounds[]|select(.tag==$t).tls.reality.handshake.server)=$v' "$RS_SINGBOX_CONFIG" > "$tmp";; *) return 1;; esac; rs_transaction_apply "$tmp" "$RS_SINGBOX_CONFIG" rs_sb_validate rs_sb_post_apply >/dev/null; local rc=$?; rm -f "$tmp"; return "$rc"; }
rs_sb_edit(){ rs_locked_call _rs_sb_edit "$@"; }
_rs_sb_delete(){ local tag=$1 tmp count sf st; count=$(jq --arg t "$tag" '[.inbounds[]?|select(.tag==$t)]|length' "$RS_SINGBOX_CONFIG"); [[ $count == 1 ]] || return 1; rs_state_init; sf=$(rs_state_file); tmp=$(mktemp); st=$(mktemp); jq --arg t "$tag" '.inbounds|=map(select(.tag!=$t))' "$RS_SINGBOX_CONFIG" > "$tmp" && jq --arg t "$tag" 'del(.singbox.instances[$t])' "$sf" >"$st" && chmod 600 "$st" || { rm -f "$tmp" "$st"; return 1; }; rs_transaction_apply_pair "$tmp" "$RS_SINGBOX_CONFIG" "$st" "$sf" rs_sb_validate rs_sb_post_apply; local rc=$?; rm -f "$tmp" "$st"; return "$rc"; }
rs_sb_delete(){ rs_locked_call _rs_sb_delete "$@"; }
rs_sb_clone(){ local tag=$1 name=$2 port=$3 type; type=$(jq -r --arg t "$tag" '.inbounds[]|select(.tag==$t)|.type' "$RS_SINGBOX_CONFIG"); rs_sb_add "$type" "$name" "$port"; }
_rs_sb_migrate(){
 rs_sb_ensure; rs_state_init; local sf tmp tag type private public; sf=$(rs_state_file)
 while IFS=$'\t' read -r tag type private; do
 [[ -n $tag ]] || continue; public=''
  private=${private%$'\r'}
  if [[ $type == vless || $type == anytls ]] && [[ -n $private && $private != null ]]; then public=$(rs_sb_reality_public_from_private "$private" 2>/dev/null || true); fi
  tmp="$sf.tmp-$$"
  jq --arg t "$tag" --arg y "$type" --arg pk "$public" '.singbox.instances[$t] //= {name:$t,type:$y,managed:false,legacy:true} | if $pk != "" and ((.singbox.instances[$t].public_key // "") == "") then .singbox.instances[$t].public_key=$pk else . end' "$sf" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$sf" || { rm -f "$tmp"; return 1; }
 done < <(jq -r '.inbounds[]?|select(.type=="shadowsocks" or .type=="hysteria2" or .type=="tuic" or .type=="vless" or .type=="anytls")|[.tag,.type,(.tls.reality.private_key//"")]|@tsv' "$RS_SINGBOX_CONFIG")
}
rs_sb_migrate(){ rs_locked_call _rs_sb_migrate "$@"; }
rs_sb_urlencode(){ local value; value=$(tr -d '\r\n'); printf '%s' "$value" | jq -sRr @uri | tr -d '\r\n'; }
rs_sb_link(){
 local tag=$1 host=$2 row type port public sid password
 row=$(jq -c --arg t "$tag" '.inbounds[]|select(.tag==$t)' "$RS_SINGBOX_CONFIG") || return 1; [[ -n $row ]] || return 1
 type=$(jq -r .type <<< "$row"); port=$(jq -r .listen_port <<< "$row")
 case $type in
  shadowsocks) local method encoded; method=$(jq -r .method<<<"$row"); password=$(jq -r .password<<<"$row"); encoded=$(printf '%s' "$method:$password"|base64|tr -d '\n'); printf 'ss://%s@%s:%s#%s\n' "$encoded" "$host" "$port" "$tag" ;;
  hysteria2) password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'hy2://%s@%s:%s/?insecure=1#%s\n' "$password" "$host" "$port" "$tag" ;;
  tuic) password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'tuic://%s:%s@%s:%s/?congestion_control=bbr&insecure=1#%s\n' "$(jq -r '.users[0].uuid'<<<"$row")" "$password" "$host" "$port" "$tag" ;;
  vless) public=$(rs_state_get ".singbox.instances[\"$tag\"].public_key"); [[ $public =~ ^[A-Za-z0-9_-]{32,64}$ ]] || { rs_die 'Reality public key is unavailable for this instance'; return 1; }; sid=$(jq -r '.tls.reality.short_id[0]'<<<"$row"); printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#%s\n' "$(jq -r '.users[0].uuid'<<<"$row")" "$host" "$port" "$(jq -r '.tls.server_name'<<<"$row")" "$public" "$sid" "$tag" ;;
  anytls) public=$(rs_state_get ".singbox.instances[\"$tag\"].public_key"); [[ $public =~ ^[A-Za-z0-9_-]{32,64}$ ]] || { rs_die 'Reality public key is unavailable for this instance'; return 1; }; sid=$(jq -r '.tls.reality.short_id[0]'<<<"$row"); password=$(jq -r '.users[0].password'<<<"$row"|rs_sb_urlencode); printf 'anytls://%s@%s:%s/?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#%s\n' "$password" "$host" "$port" "$(jq -r '.tls.server_name'<<<"$row")" "$public" "$sid" "$tag" ;;
 esac
}
