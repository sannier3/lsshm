# shellcheck shell=bash
# =============================================================================
# common.sh - shared helpers: version, paths, logging, prompts, temp files
# =============================================================================
# This module has no dependencies on other LSSHM modules and must be sourced
# (or concatenated) first.

# The build script replaces the token below with the content of the VERSION
# file. When running directly from src/ the token stays literal and the guard
# below falls back to a development version string.
LSSHM_VERSION="@@LSSHM_VERSION@@"
case "$LSSHM_VERSION" in
    *@@*) LSSHM_VERSION="0.1.0-dev" ;;
esac

LSSHM_NAME="LSSHM"
LSSHM_LONG_NAME="LSSHM - Local SSH Manager"
LSSHM_REPO_RAW="${LSSHM_REPO_RAW:-https://raw.githubusercontent.com/sannier3/lsshm/main}"

# -----------------------------------------------------------------------------
# XDG base directories
# -----------------------------------------------------------------------------
lsshm_init_paths() {
    LSSHM_HOME="${HOME:-/root}"
    LSSHM_XDG_CONFIG="${XDG_CONFIG_HOME:-$LSSHM_HOME/.config}"
    LSSHM_XDG_DATA="${XDG_DATA_HOME:-$LSSHM_HOME/.local/share}"
    LSSHM_XDG_STATE="${XDG_STATE_HOME:-$LSSHM_HOME/.local/state}"
    LSSHM_XDG_CACHE="${XDG_CACHE_HOME:-$LSSHM_HOME/.cache}"
    LSSHM_BIN_DIR="$LSSHM_HOME/.local/bin"

    LSSHM_CONFIG_DIR="$LSSHM_XDG_CONFIG/lsshm"
    LSSHM_DATA_DIR="$LSSHM_XDG_DATA/lsshm"
    LSSHM_STATE_DIR="$LSSHM_XDG_STATE/lsshm"
    LSSHM_CACHE_DIR="$LSSHM_XDG_CACHE/lsshm"

    LSSHM_CONFIG_FILE="$LSSHM_CONFIG_DIR/config"
    LSSHM_BACKUP_DIR="$LSSHM_STATE_DIR/backups"
    LSSHM_LOG_FILE="$LSSHM_STATE_DIR/lsshm.log"
    LSSHM_INSTALL_TARGET="$LSSHM_DATA_DIR/lsshm.sh"
    LSSHM_BIN_LINK="$LSSHM_BIN_DIR/lsshm"
}

# -----------------------------------------------------------------------------
# Colors (disabled when not writing to a terminal or NO_COLOR is set)
# -----------------------------------------------------------------------------
lsshm_init_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${LSSHM_NO_COLOR:-0}" != "1" ]; then
        LSSHM_C_RESET="$(printf '\033[0m')"
        LSSHM_C_BOLD="$(printf '\033[1m')"
        LSSHM_C_DIM="$(printf '\033[2m')"
        LSSHM_C_RED="$(printf '\033[31m')"
        LSSHM_C_GREEN="$(printf '\033[32m')"
        LSSHM_C_YELLOW="$(printf '\033[33m')"
    else
        LSSHM_C_RESET=""; LSSHM_C_BOLD=""; LSSHM_C_DIM=""
        LSSHM_C_RED=""; LSSHM_C_GREEN=""; LSSHM_C_YELLOW=""
    fi
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
lsshm_log() {
    # lsshm_log LEVEL MESSAGE...
    local level="$1"; shift
    local msg="$*"
    if [ -n "${LSSHM_LOG_FILE:-}" ]; then
        local dir; dir="$(dirname "$LSSHM_LOG_FILE")"
        if [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null; then
            printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$msg" \
                >>"$LSSHM_LOG_FILE" 2>/dev/null || true
        fi
    fi
}

lsshm_info()  { printf '%s\n' "$*"; lsshm_log INFO "$*"; }
lsshm_note()  { printf '%s%s%s\n' "${LSSHM_C_DIM:-}" "$*" "${LSSHM_C_RESET:-}" >&2; lsshm_log INFO "$*"; }
lsshm_ok()    { printf '%s%s%s\n' "${LSSHM_C_GREEN:-}" "$*" "${LSSHM_C_RESET:-}"; lsshm_log OK "$*"; }
lsshm_warn()  { printf '%s%s%s\n' "${LSSHM_C_YELLOW:-}" "$*" "${LSSHM_C_RESET:-}" >&2; lsshm_log WARN "$*"; }
lsshm_error() { printf '%s%s%s\n' "${LSSHM_C_RED:-}" "$*" "${LSSHM_C_RESET:-}" >&2; lsshm_log ERROR "$*"; }

lsshm_die() {
    lsshm_error "$*"
    exit 1
}

lsshm_header() {
    printf '%s%s%s\n' "${LSSHM_C_BOLD:-}" "$LSSHM_LONG_NAME" "${LSSHM_C_RESET:-}"
    printf '%sv%s%s\n\n' "${LSSHM_C_DIM:-}" "$LSSHM_VERSION" "${LSSHM_C_RESET:-}"
}

# -----------------------------------------------------------------------------
# Prompts
# -----------------------------------------------------------------------------
lsshm_is_interactive() {
    [ -t 0 ] && [ -t 1 ] && [ "${LSSHM_ASSUME_YES:-0}" != "1" ]
}

lsshm_prompt() {
    # lsshm_prompt PROMPT [DEFAULT] -> echoes answer
    local prompt="$1" default="${2:-}" answer=""
    if ! lsshm_is_interactive; then
        printf '%s' "$default"
        return 0
    fi
    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " answer </dev/tty || answer=""
    else
        read -r -p "$prompt: " answer </dev/tty || answer=""
    fi
    printf '%s' "${answer:-$default}"
}

lsshm_confirm() {
    # lsshm_confirm PROMPT [default_yes] -> return 0 for yes
    local prompt="$1" default="${2:-no}" answer=""
    if [ "${LSSHM_ASSUME_YES:-0}" = "1" ]; then
        return 0
    fi
    if ! lsshm_is_interactive; then
        [ "$default" = "yes" ]
        return
    fi
    local hint="[o/N]"
    [ "$default" = "yes" ] && hint="[O/n]"
    read -r -p "$prompt $hint " answer </dev/tty || answer=""
    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
        o|oui|y|yes) return 0 ;;
        n|non|no)    return 1 ;;
        "")          [ "$default" = "yes" ] ;;
        *)           return 1 ;;
    esac
}

lsshm_pause() {
    lsshm_is_interactive || return 0
    read -r -p "Appuyez sur Entrée pour continuer..." _ </dev/tty || true
}

# -----------------------------------------------------------------------------
# Temporary files (tracked and cleaned on exit)
# -----------------------------------------------------------------------------
LSSHM_TMPFILES=()

lsshm_mktemp() {
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/lsshm.XXXXXX")" || lsshm_die "Impossible de créer un fichier temporaire."
    LSSHM_TMPFILES+=("$tmp")
    printf '%s' "$tmp"
}

lsshm_cleanup() {
    local f
    for f in "${LSSHM_TMPFILES[@]:-}"; do
        [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
    done
}

# -----------------------------------------------------------------------------
# Small utilities
# -----------------------------------------------------------------------------
lsshm_have() { command -v "$1" >/dev/null 2>&1; }

lsshm_yesno_label() {
    case "$1" in
        yes|true|on|1) printf 'oui' ;;
        no|false|off|0) printf 'non' ;;
        "") printf 'non défini' ;;
        *) printf '%s' "$1" ;;
    esac
}

# Ensure the runtime directories exist.
lsshm_ensure_dirs() {
    local d
    for d in "$LSSHM_CONFIG_DIR" "$LSSHM_DATA_DIR" "$LSSHM_STATE_DIR" \
             "$LSSHM_CACHE_DIR" "$LSSHM_BACKUP_DIR"; do
        [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || true
    done
}
