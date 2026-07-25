#!/usr/bin/env bash
rs_service_detect_init(){ [[ -n ${RS_INIT_SYSTEM:-} ]] || rs_detect_platform; }
rs_service(){
  local action=$1 name=$2 init; rs_service_detect_init || return 1; init=$RS_INIT_SYSTEM
  if [[ $init == openrc ]]; then
    case $action in enable) rc-update add "$name" default;; disable) rc-update del "$name" default;; is-enabled) rc-update show default 2>/dev/null | grep -Eq "(^|[[:space:]])$name([[:space:]]|$)";; is-active) rc-service "$name" status;; status) rc-service "$name" status;; *) rc-service "$name" "$action";; esac
  else
    case $action in daemon-reload) systemctl daemon-reload;; is-active) systemctl is-active --quiet "$name";; *) systemctl "$action" "$name";; esac
  fi
}
rs_service_exists(){
 local name=$1 init; rs_service_detect_init || return 1; init=$RS_INIT_SYSTEM
 if [[ $init == openrc ]]; then [[ -x $(rs_path "/etc/init.d/$name") ]] || rc-service "$name" status >/dev/null 2>&1
 else [[ -f $(rs_path "/etc/systemd/system/$name.service") || -f $(rs_path "/usr/lib/systemd/system/$name.service") ]] || systemctl cat "$name" >/dev/null 2>&1
 fi
}
rs_service_reload_and_check(){ local name=$1; [[ ${RS_TEST_MODE:-0} == 1 ]] && return 0; rs_service_detect_init || return 1; rs_service_exists "$name" || return 0; rs_service restart "$name" && rs_service is-active "$name"; }
