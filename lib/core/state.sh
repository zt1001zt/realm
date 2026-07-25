#!/usr/bin/env bash
: "${RS_STATE_DIR:=/etc/rs-manager}"
rs_state_file(){ printf '%s/state.json\n' "$RS_STATE_DIR"; }
rs_state_init(){ mkdir -p "$RS_STATE_DIR"; local file; file=$(rs_state_file); [[ -s $file ]] || printf '%s\n' '{"version":1,"singbox":{"instances":{}},"realm":{"rules":{}},"tuning":{}}' > "$file"; chmod 600 "$file" 2>/dev/null || true; }
rs_state_get(){ rs_state_init; jq -r "$1 // empty" "$(rs_state_file)" | tr -d '\r'; }
rs_state_set(){ rs_state_init; local path=$1 value=$2 file tmp; file=$(rs_state_file); tmp="$file.tmp-$$"; jq --arg value "$value" "$path = \$value" "$file" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$file"; }
rs_state_set_json(){ rs_state_init; local path=$1 value=$2 file tmp; file=$(rs_state_file); tmp="$file.tmp-$$"; jq --argjson value "$value" "$path = \$value" "$file" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$file"; }
