#!/usr/bin/env bash
: "${RS_SINGBOX_VERSION:=1.13.14}"
: "${RS_REALM_VERSION:=2.9.4}"
rs_component_asset(){
 local component=$1 arch libc asset sha version base
 arch=${RS_ARCH_OVERRIDE:-$(rs_arch)}; [[ ${RS_OS_FAMILY:-} == alpine ]] && libc=musl || libc=glibc
 case "$component:$arch:$libc" in
  sing-box:amd64:glibc) sha=aae9172317c61760aae3dafcde889b2e51b7ea590c40d2b3c7ccdeae14b361b6;;
  sing-box:arm64:glibc) sha=08d37b2bf12145ec44307333490cecca4c917df054cd8e27a210f8d9cdbe0fd9;;
  sing-box:amd64:musl) sha=d5b46de6498427bccfeb87dbafcde4dbefdfe35680020d07d286ad915f0bfb34;;
  sing-box:arm64:musl) sha=edec18488af35a93cf8b362063146fdd7b557ef9862710ee77a1f4adb5c70118;;
  realm:amd64:glibc) sha=9dec109386b8abc828b452d0d1cecde35b7a2f8cfa93eae757fe9c248ad07ddd;;
  realm:arm64:glibc) sha=1f7f06e82fe0ea798b5c8e8e32906ee212a7085629a1c5cef9957ca270fcad99;;
  realm:amd64:musl) sha=a19b86c4ae4642d5864821b41d23633c0c91df279a88496c05834dc584169175;;
  realm:arm64:musl) sha=0195e77ca99713166e25ff85fefe042049c79fdaddf500e8ffd9ba77494a029c;;
  *) return 1;;
 esac
 if [[ $component == sing-box ]]; then
  version=$RS_SINGBOX_VERSION; asset="sing-box-$version-linux-$arch-$libc.tar.gz"; base="https://github.com/SagerNet/sing-box/releases/download/v$version"
 else
  version=$RS_REALM_VERSION; [[ $arch == amd64 ]] && arch=x86_64 || arch=aarch64; [[ $libc == glibc ]] && libc=gnu
  asset="realm-$arch-unknown-linux-$libc.tar.gz"; base="https://github.com/zhboner/realm/releases/download/v$version"
 fi
 printf '%s\t%s/%s\t%s\n' "$version" "$base" "$asset" "$sha"
}
rs_download(){ local url=$1 output=$2; case $url in file://*) cp "${url#file://}" "$output";; *) curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 "$url" -o "$output";; esac; }
rs_component_archive_safe(){ ! tar -tzf "$1" | grep -Eq '(^/|(^|/)\.\.(/|$))'; }
rs_component_binary_validate(){ local file=$1; [[ -x $file ]] || return 1; if [[ ${RS_TEST_MODE:-0} != 1 ]]; then case ${RS_COMPONENT_ACTIVE:-} in sing-box) "$file" version >/dev/null;; realm) "$file" --version >/dev/null 2>&1;; *) return 1;; esac; fi; }
rs_component_unit_path(){ local component=$1; if [[ ${RS_INIT_SYSTEM:-systemd} == openrc ]]; then rs_path "/etc/init.d/$component"; else rs_path "/etc/systemd/system/$component.service"; fi; }
rs_component_render_service(){
 local component=$1 binary config; binary=$(rs_path "/usr/local/bin/$component")
 case $component in sing-box) config=$RS_SINGBOX_CONFIG;; realm) config=$RS_REALM_CONFIG;; *) return 1;; esac
 if [[ ${RS_INIT_SYSTEM:-systemd} == openrc ]]; then
  cat <<EOF
#!/sbin/openrc-run
name="$component"
command="$binary"
command_args="$( [[ $component == sing-box ]] && printf 'run -c %s' "$config" || printf '%s' "-c $config" )"
command_background="yes"
pidfile="/run/$component.pid"
output_log="/var/log/$component.log"
error_log="/var/log/$component.err"
depend() { need net; }
EOF
 else
  cat <<EOF
[Unit]
Description=RS Manager $component service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$binary $( [[ $component == sing-box ]] && printf 'run -c %s' "$config" || printf '%s' "-c $config" )
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
 fi
}
rs_component_write_service(){ local component=$1 target tmp; target=$(rs_component_unit_path "$component"); tmp=$(mktemp); rs_component_render_service "$component">"$tmp"; mkdir -p "$(dirname "$target")"; chmod +x "$tmp"; rs_atomic_install "$tmp" "$target"; rm -f "$tmp"; }
rs_component_capture_service_state(){
 local component=$1
 RS_COMPONENT_WAS_PRESENT=false; RS_COMPONENT_WAS_ACTIVE=false; RS_COMPONENT_WAS_ENABLED=false
 if rs_service_exists "$component"; then
  RS_COMPONENT_WAS_PRESENT=true
  rs_service is-active "$component" >/dev/null 2>&1 && RS_COMPONENT_WAS_ACTIVE=true
  rs_service is-enabled "$component" >/dev/null 2>&1 && RS_COMPONENT_WAS_ENABLED=true
 fi
 export RS_COMPONENT_WAS_PRESENT RS_COMPONENT_WAS_ACTIVE RS_COMPONENT_WAS_ENABLED
}
rs_component_post_apply(){
 [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0
 local component=${RS_COMPONENT_ACTIVE:?}
 if [[ ${RS_TRANSACTION_ROLLBACK:-0} == 1 ]]; then
  local rc=0
  if [[ ${RS_INIT_SYSTEM:-systemd} == systemd ]]; then rs_service daemon-reload "$component" >/dev/null 2>&1 || rc=1; fi
  if [[ ${RS_COMPONENT_WAS_ENABLED:-false} == true ]]; then rs_service enable "$component" >/dev/null 2>&1 || rc=1; else rs_service disable "$component" >/dev/null 2>&1 || rc=1; fi
  if [[ ${RS_COMPONENT_WAS_ACTIVE:-false} == true ]]; then rs_service start "$component" >/dev/null 2>&1 || rc=1; else rs_service stop "$component" >/dev/null 2>&1 || rc=1; fi
  return "$rc"
 fi
 if [[ ${RS_INIT_SYSTEM:-systemd} == systemd ]]; then rs_service daemon-reload "$component" || return 1; fi
 rs_service enable "$component" && rs_service restart "$component" && rs_service is-active "$component"
}
rs_component_install(){
 local component=$1 row version url expected work archive binary unit_candidate binary_target unit_target found actual
 [[ $component == sing-box || $component == realm ]] || return 1; rs_require_root || return 1
 [[ -n ${RS_OS_FAMILY:-} && -n ${RS_INIT_SYSTEM:-} ]] || rs_detect_platform || return 1
 rs_component_capture_service_state "$component"
 row=$(rs_component_asset "$component") || return 1; IFS=$'\t' read -r version url expected <<<"$row"; [[ $expected =~ ^[0-9a-f]{64}$ ]] || { rs_die 'Missing trusted SHA-256'; return 1; }
 work=$(mktemp -d); chmod 700 "$work"; archive="$work/archive.tar.gz"
 rs_download "$url" "$archive" || { rm -rf "$work"; return 1; }; actual=$(sha256sum "$archive"|awk '{print $1}'); [[ $actual == "$expected" ]] || { rs_die "SHA-256 mismatch for $component $version"; rm -rf "$work"; return 1; }
 rs_component_archive_safe "$archive" || { rs_die 'Unsafe archive paths'; rm -rf "$work"; return 1; }; tar -xzf "$archive" -C "$work" || { rm -rf "$work"; return 1; }
 found=$(find "$work" -type f -name "$component" -print -quit); [[ -n $found ]] || { rm -rf "$work"; return 1; }; binary="$work/$component.candidate"; cp "$found" "$binary"; chmod 755 "$binary"
 binary_target=$(rs_path "/usr/local/bin/$component"); unit_target=$(rs_component_unit_path "$component"); unit_candidate="$work/$component.service.candidate"; rs_component_render_service "$component">"$unit_candidate"; chmod 755 "$unit_candidate"; mkdir -p "$(dirname "$binary_target")" "$(dirname "$unit_target")"
 if [[ $component == sing-box ]]; then rs_sb_ensure; rs_sb_migrate; else rs_realm_ensure; rs_realm_migrate; fi
 RS_COMPONENT_ACTIVE=$component; export RS_COMPONENT_ACTIVE
 rs_transaction_apply_pair "$binary" "$binary_target" "$unit_candidate" "$unit_target" rs_component_binary_validate rs_component_post_apply || { unset RS_COMPONENT_ACTIVE; rm -rf "$work"; return 1; }
 unset RS_COMPONENT_ACTIVE; rm -rf "$work"; rs_info "Installed $component $version"
}
rs_component_action(){ local action=$1 component=$2; case $action in install|upgrade) rs_component_install "$component";; start|stop|restart|status) rs_service "$action" "$component";; *) return 1;; esac; }
