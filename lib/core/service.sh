#!/usr/bin/env bash
rs_service(){
  local action=$1 name=$2 init=${RS_INIT_SYSTEM:-systemd}
  if [[ $init == openrc ]]; then
    case $action in enable) rc-update add "$name" default;; disable) rc-update del "$name" default;; is-active) rc-service "$name" status;; status) rc-service "$name" status;; *) rc-service "$name" "$action";; esac
  else
    case $action in is-active) systemctl is-active --quiet "$name";; *) systemctl "$action" "$name";; esac
  fi
}
