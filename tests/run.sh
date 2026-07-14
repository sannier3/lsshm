#!/usr/bin/env bash
# =============================================================================
# run.sh - LSSHM test runne
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"

export LSSHM_TESTS_DIR="$TESTS_DIR"
export LSSHM_ROOT_DIR="$ROOT_DIR"
export LSSHM_SRC_DIR="$SRC_DIR"

LSSHM_TEST_TOTAL=0
LSSHM_TEST_FAIL=0

# shellcheck disable=SC2317
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    LSSHM_TEST_TOTAL=$((LSSHM_TEST_TOTAL+1))
    if [ "$expected" = "$actual" ]; then
        printf '  ok   %s\n' "$msg"
    else
        LSSHM_TEST_FAIL=$((LSSHM_TEST_FAIL+1))
        printf '  FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' "$msg" "$expected" "$actual"
    fi
}

assert_true() {
    local msg="${2:-}"
    LSSHM_TEST_TOTAL=$((LSSHM_TEST_TOTAL+1))
    if eval "$1"; then
        printf '  ok   %s\n' "$msg"
    else
        LSSHM_TEST_FAIL=$((LSSHM_TEST_FAIL+1))
        printf '  FAIL %s (expected success: %s)\n' "$msg" "$1"
    fi
}

assert_false() {
    local msg="${2:-}"
    LSSHM_TEST_TOTAL=$((LSSHM_TEST_TOTAL+1))
    if eval "$1"; then
        LSSHM_TEST_FAIL=$((LSSHM_TEST_FAIL+1))
        printf '  FAIL %s (expected failure: %s)\n' "$msg" "$1"
    else
        printf '  ok   %s\n' "$msg"
    fi
}

# Source the library modules (definitions only; no dispatch).
lsshm_source_all() {
    local m
    for m in common.sh platform.sh privileges.sh backup.sh server.sh \
             server_config.sh rollback.sh users.sh authorized_keys.sh \
             local_keys.sh ssh_agent.sh hosts.sh known_hosts.sh logs.sh \
             audit.sh updater.sh cli.sh dialog.sh main.sh; do
        # shellcheck disable=SC1090
        . "$SRC_DIR/$m"
    done
    lsshm_init_paths
    # shellcheck disable=SC2034  # consumed by lsshm_init_colors
    LSSHM_NO_COLOR=1
    lsshm_init_colors
}

main() {
    lsshm_source_all
    local t
    for t in "$TESTS_DIR"/test_*.sh; do
        [ -f "$t" ] || continue
        printf '== %s ==\n' "$(basename "$t")"
        # shellcheck disable=SC1090
        . "$t"
    done
    printf '\nTotal: %d, Failures: %d\n' "$LSSHM_TEST_TOTAL" "$LSSHM_TEST_FAIL"
    [ "$LSSHM_TEST_FAIL" -eq 0 ]
}

main "$@"
