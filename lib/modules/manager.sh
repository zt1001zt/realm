#!/usr/bin/env bash

RS_MANAGER_INSTALL_MARKER=RS_MANAGER_INSTALL_V1

rs_manager_uninstall(){
 local prefix=${1:-${RS_PREFIX:-/usr/local}} lib bin marker wrapper
 prefix=${prefix%/}
 case $prefix in
  /*) ;;
  *) rs_die 'RS Manager 安装前缀必须是绝对路径'; return 1 ;;
 esac
 case "/$prefix/" in
  *'/../'*|*'/./'*) rs_die 'RS Manager 安装前缀包含不安全路径'; return 1 ;;
 esac
 [[ -n $prefix && $prefix != / ]] || { rs_die '拒绝使用不安全的安装前缀'; return 1; }
 lib="$prefix/lib/rs-manager"; bin="$prefix/bin"; marker="$lib/.rs-manager-install"
 [[ -f $marker && $(cat "$marker" 2>/dev/null) == "$RS_MANAGER_INSTALL_MARKER" ]] || {
  rs_die "无法确认 RS Manager 所有权，拒绝删除：$lib"
  return 1
 }
 for wrapper in "$bin/rs" "$bin/sb"; do
  [[ -f $wrapper ]] || { rs_die "RS Manager 包装器不存在：$wrapper"; return 1; }
  grep -Fq "$lib" "$wrapper" || { rs_die "无法确认包装器所有权，拒绝删除：$wrapper"; return 1; }
 done
 rm -f -- "$bin/rs" "$bin/sb" || return 1
 rm -rf -- "$lib" || return 1
 printf 'RS Manager 已卸载；Sing-box、Realm、配置、状态、备份和调优均已保留。\n'
}
