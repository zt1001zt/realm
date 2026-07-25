#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"; DIR=$(cd "$(dirname "$0")/.."&&pwd); source "$DIR/tests/test_helper.sh"; source "$DIR/lib/modules/diagnostics.sh"
out=$(printf '%s\n' 'password=secret UUID=123e4567-e89b-12d3-a456-426614174000 private_key=abc token=xyz' | rs_diag_redact)
assert_false grep -q 'secret\|123e4567\|abc\|xyz' <<< "$out"
assert_true grep -q 'REDACTED' <<< "$out"
json=$(printf '%s\n' '{"password": "json-secret", "private_key":"json-key", "uuid": "json-uuid", "nested":{"token":"json-token"}}' | rs_diag_redact)
assert_false grep -q 'json-secret\|json-key\|json-uuid\|json-token' <<< "$json"
assert_true grep -q 'REDACTED' <<< "$json"
finish
