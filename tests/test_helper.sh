#!/usr/bin/env bash
set -euo pipefail
TESTS=0
FAILURES=0
assert_eq(){ TESTS=$((TESTS+1)); if [[ "$1" != "$2" ]]; then echo "not ok $TESTS - expected [$2], got [$1]"; FAILURES=$((FAILURES+1)); else echo "ok $TESTS"; fi; }
assert_true(){ TESTS=$((TESTS+1)); if ! "$@"; then echo "not ok $TESTS - $*"; FAILURES=$((FAILURES+1)); else echo "ok $TESTS"; fi; }
assert_false(){ TESTS=$((TESTS+1)); if "$@"; then echo "not ok $TESTS - unexpectedly true: $*"; FAILURES=$((FAILURES+1)); else echo "ok $TESTS"; fi; }
finish(){ [[ $FAILURES -eq 0 ]] || exit 1; echo "1..$TESTS"; }
make_root(){ TEST_ROOT=$(mktemp -d); export RS_ROOT="$TEST_ROOT" RS_TEST_MODE=1; mkdir -p "$TEST_ROOT/etc" "$TEST_ROOT/run" "$TEST_ROOT/tmp"; }
cleanup_root(){ rm -rf "${TEST_ROOT:-}"; }
