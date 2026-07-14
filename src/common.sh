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
# True when stdin/stdout is a TTY, or when /dev/tty is available (IDE
# terminals, sudo, Git Bash on Windows often lack -t 0 but still have /dev/tty).
lsshm_have_tty() {
    [ -e /dev/tty ] 2>/dev/null && [ -r /dev/tty ] && [ -w /dev/tty ]
}

lsshm_is_interactive() {
    [ "${LSSHM_ASSUME_YES:-0}" != "1" ] || return 1
    [ -t 0 ] && [ -t 1 ] && return 0
    lsshm_have_tty && return 0
    return 1
}

lsshm_require_interactive() {
    if lsshm_is_interactive; then
        return 0
    fi
    lsshm_error "Un terminal interactif est requis pour le menu."
    lsshm_info "Sans menu : lsshm status | lsshm doctor | lsshm server status | lsshm key list"
    lsshm_info "Pour installer : curl -fsSL .../lsshm.sh | bash -s -- install"
    exit 1
}

lsshm_tty_restore() {
    stty sane 2>/dev/null || true
}

lsshm_uses_dialog_ui() {
    [ "${LSSHM_UI_MODE:-0}" = "1" ] && lsshm_have dialog
}

# Read one line from stdin or /dev/tty. Sets the named variable on success.
lsshm_read_line() {
    local __var="$1" __prompt="$2" __line=""
    if [ -t 0 ]; then
        IFS= read -r -p "$__prompt" __line || return 1
    elif lsshm_have_tty; then
        IFS= read -r -p "$__prompt" __line </dev/tty || return 1
    else
        return 1
    fi
    printf -v "$__var" '%s' "$__line"
    return 0
}

lsshm_prompt() {
    # lsshm_prompt PROMPT [DEFAULT] -> echoes answer
    local prompt="$1" default="${2:-}" answer="" msg=""
    if ! lsshm_is_interactive; then
        [ -n "$default" ] && { printf '%s' "$default"; return 0; }
        return 1
    fi
    if lsshm_uses_dialog_ui; then
        lsshm_tty_restore
        answer="$(dialog --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3)" || answer="$default"
        printf '%s' "${answer:-$default}"
        return 0
    fi
    if [ -n "$default" ]; then
        msg="${prompt} [${default}]: "
    else
        msg="${prompt}: "
    fi
    if lsshm_read_line answer "$msg"; then
        printf '%s' "${answer:-$default}"
    else
        printf '%s' "$default"
    fi
}

lsshm_confirm() {
    # lsshm_confirm PROMPT [default_yes] -> return 0 for yes
    local prompt="$1" default="${2:-no}" answer="" hint="[o/N]"
    if [ "${LSSHM_ASSUME_YES:-0}" = "1" ]; then
        return 0
    fi
    if ! lsshm_is_interactive; then
        [ "$default" = "yes" ]
        return
    fi
    if lsshm_uses_dialog_ui; then
        lsshm_tty_restore
        if dialog --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
            --yesno "$prompt" 10 70 3>&1 1>&2 2>&3; then
            return 0
        fi
        return 1
    fi
    [ "$default" = "yes" ] && hint="[O/n]"
    if ! lsshm_read_line answer "${prompt} ${hint} "; then
        [ "$default" = "yes" ]
        return
    fi
    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
        o|oui|y|yes) return 0 ;;
        n|non|no)    return 1 ;;
        "")          [ "$default" = "yes" ] ;;
        *)           return 1 ;;
    esac
}

lsshm_pause() {
    if lsshm_uses_dialog_ui; then
        return 0
    fi
    lsshm_is_interactive || return 0
    lsshm_read_line _ "Appuyez sur Entrée pour continuer... " || true
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
