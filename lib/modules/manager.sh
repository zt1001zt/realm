#!/usr/bin/env bash

RS_MANAGER_INSTALL_MARKER=RS_MANAGER_INSTALL_V1

rs_manager_uninstall(){
 local prefix=${1:-${RS_PREFIX:-/usr/local}} resolved lib bin marker wrapper expected actual key
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
 resolved=$(readlink -f "$prefix" 2>/dev/null) || { rs_die '无法解析 RS Manager 安装前缀'; return 1; }
 [[ $resolved == "$prefix" && ! -L $prefix && ! -L $prefix/bin && ! -L $prefix/lib && ! -L $lib ]] || {
  rs_die "RS Manager 安装路径包含符号链接，拒绝删除：$prefix"
  return 1
 }
 [[ -f $marker && ! -L $marker && $(sed -n '1p' "$marker" 2>/dev/null) == "$RS_MANAGER_INSTALL_MARKER" ]] || {
  rs_die "无法确认 RS Manager 所有权，拒绝删除：$lib"
  return 1
 }
 for wrapper in "$bin/rs" "$bin/sb"; do
  [[ -f $wrapper && ! -L $wrapper ]] || { rs_die "RS Manager 包装器不存在或不安全：$wrapper"; return 1; }
  case $wrapper in "$bin/rs")key=rs_sha256;;*)key=sb_sha256;;esac
  expected=$(sed -n "s/^${key}=//p" "$marker")
  actual=$(sha256sum "$wrapper" | awk '{print $1}')
  [[ $expected =~ ^[0-9a-f]{64}$ && $actual == "$expected" ]] || { rs_die "无法确认包装器所有权，拒绝删除：$wrapper"; return 1; }
 done
 rm -f -- "$bin/rs" "$bin/sb" || return 1
 rm -rf -- "$lib" || return 1
 printf 'RS Manager 已卸载；Sing-box、Realm、配置、状态、备份和调优均已保留。\n'
}
