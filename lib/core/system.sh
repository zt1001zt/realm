#!/usr/bin/env bash
rs_detect_platform(){
  local file; file=$(rs_path /etc/os-release); [[ -r $file ]] || return 1
  local ID='' ID_LIKE=''; source "$file"
  case "${ID,,}:${ID_LIKE,,}" in
    alpine:*) RS_OS_FAMILY=alpine; RS_PACKAGE_MANAGER=apk; RS_INIT_SYSTEM=openrc ;;
    debian:*|ubuntu:*|*:*debian*) RS_OS_FAMILY=debian; RS_PACKAGE_MANAGER=apt; RS_INIT_SYSTEM=systemd ;;
    centos:*|rhel:*|rocky:*|almalinux:*|fedora:*|*:*rhel*|*:*fedora*) RS_OS_FAMILY=rhel; if command -v dnf >/dev/null 2>&1; then RS_PACKAGE_MANAGER=dnf; else RS_PACKAGE_MANAGER=yum; fi; RS_INIT_SYSTEM=systemd ;;
    *) return 1 ;;
  esac
  export RS_OS_FAMILY RS_PACKAGE_MANAGER RS_INIT_SYSTEM
}
rs_arch(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) return 1;; esac; }
