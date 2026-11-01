#!/bin/bash
# Minimal test helpers (no external framework; works with macOS bash 3.2).

T_PASS=0
T_FAIL=0
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

# shellcheck disable=SC2034  # used by the test files that source this one
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        T_PASS=$((T_PASS + 1))
    else
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL  %s\n    expected: %s\n    actual:   %s\n' "$label" "$expected" "$actual"
    fi
}

assert_ok() {
    local label="$1"
    shift
    if "$@"; then
        T_PASS=$((T_PASS + 1))
    else
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL  %s (expected success: %s)\n' "$label" "$*"
    fi
}

assert_fails() {
    local label="$1"
    shift
    if "$@"; then
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL  %s (expected failure: %s)\n' "$label" "$*"
    else
        T_PASS=$((T_PASS + 1))
    fi
}

# Points the stack-config module at a fresh .env containing $1 (may be empty).
use_env() {
    STACK_ENV_FILE="$T_TMP/.env"
    export STACK_ENV_FILE
    printf '%s' "$1" > "$STACK_ENV_FILE"
}

finish() {
    printf '  %s: %d passed, %d failed\n' "$(basename "$0")" "$T_PASS" "$T_FAIL"
    [[ $T_FAIL -eq 0 ]]
}
