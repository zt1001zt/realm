#!/usr/bin/env bash
rs_diag_redact(){ sed -E '
 s/("([Pp]assword|UUID|uuid|private_key|token|secret)"[[:space:]]*:[[:space:]]*")[^"]*(")/\1REDACTED\3/g
 s/(([Pp]assword|UUID|uuid|private_key|token|secret)[[:space:]]*[=:][[:space:]]*)"[^"]*"/\1REDACTED/g
 s/(([Pp]assword|UUID|uuid|private_key|token|secret)[[:space:]]*[=:][[:space:]]*)[^[:space:]",]+/\1REDACTED/g
 s#(://)[^/@:]+(:[^/@]+)?@#\1REDACTED@#g
'; }
rs_diag_run(){
 echo '=== RS Manager Diagnostics ==='
 command -v sing-box >/dev/null 2>&1&&sing-box version|head -n1||echo 'sing-box: not installed'
 command -v realm >/dev/null 2>&1&&realm --version 2>/dev/null|head -n1||echo 'realm: not installed'
 rs_tune_status
 if [[ -f ${RS_SINGBOX_CONFIG:-/etc/sing-box/config.json} ]]; then jq empty "${RS_SINGBOX_CONFIG:-/etc/sing-box/config.json}"&&echo 'sing-box config: valid'||echo 'sing-box config: INVALID'; fi
 if [[ -f ${RS_REALM_CONFIG:-/root/.realm/config.toml} ]]; then rs_realm_validate "${RS_REALM_CONFIG:-/root/.realm/config.toml}"&&echo 'realm config: valid'||echo 'realm config: INVALID'; fi
 command -v ss >/dev/null 2>&1 && { echo '=== Listening sockets ==='; ss -H -lntu 2>/dev/null || true; }
 for service in sing-box realm; do if rs_service_exists "$service" 2>/dev/null; then rs_service status "$service" 2>&1 || true; fi; done
}
