# shellcheck shell=bash
# =============================================================================
# main.sh - entry point, argument parsing, command dispatch, install/uninstall
# =============================================================================

# Path to the running script (may be empty when piped from curl | bash).
lsshm_self_path() {
    local self="${BASH_SOURCE[0]:-$0}"
    if [ -f "$self" ]; then
        ( cd "$(dirname "$self")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$self")" )
    fi
}

lsshm_bootstrap() {
    lsshm_init_paths
    lsshm_init_colors
    lsshm_init_privileges
    lsshm_detect_platform
    lsshm_ensure_dirs
    lsshm_config_write_default
    lsshm_config_load
    lsshm_i18n_init
    trap lsshm_cleanup EXIT INT TERM
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
lsshm_usage() {
    printf '%s v%s\n\n' "$LSSHM_LONG_NAME" "$LSSHM_VERSION"
    lsshm_out 'Usage:'
    printf '  lsshm                     %s\n' "$(lsshm_t 'Open the CLI menu')"
    printf '  lsshm ui | --ui           %s\n' "$(lsshm_t 'Open the dialog interface')"
    printf '  lsshm status              %s\n' "$(lsshm_t 'Show local SSH status')"
    printf '  lsshm doctor              %s\n' "$(lsshm_t 'Environment diagnostics')"
    printf '  lsshm audit               %s\n' "$(lsshm_t 'Security audit')"
    printf '  lsshm update [rollback]   %s\n' "$(lsshm_t 'Update LSSHM (or roll back)')"
    printf '  lsshm install             %s\n' "$(lsshm_t 'Install LSSHM into ~/.local')"
    printf '  lsshm uninstall           %s\n' "$(lsshm_t 'Uninstall LSSHM')"
    printf '  lsshm version             %s\n' "$(lsshm_t 'Show the version')"
    printf '  lsshm help                %s\n' "$(lsshm_t 'Show this help')"
    printf '\n'
    lsshm_out 'Global options:'
    printf '  --user NAME               %s\n' "$(lsshm_t "Manage NAME's SSH files (access, keys, hosts)")"
    printf '  --lang CODE               %s\n' "$(lsshm_tf 'Interface language (%s)' "$LSSHM_LANGS")"
    printf '  --ui                      %s\n' "$(lsshm_t 'Force the dialog interface')"
    printf '  -y, --yes                 %s\n' "$(lsshm_t 'Answer yes automatically (non-interactive)')"
    printf '  --no-color                %s\n' "$(lsshm_t 'Disable color')"
    printf '  -V, --version             %s\n' "$(lsshm_t 'Show the version')"
    printf '  -h, --help                %s\n' "$(lsshm_t 'Show this help')"
    printf '\n'
    lsshm_out 'Local SSH server:'
    printf '  lsshm server status|install|start|stop|restart|reload|enable|disable\n'
    printf '  lsshm server config|test|logs\n'
    printf '\n'
    lsshm_out 'Incoming access (keys allowed HERE):'
    printf '  lsshm access list [--user U]\n'
    printf '  lsshm access add [--user U]\n'
    printf '  lsshm access remove [--user U]\n'
    printf '  lsshm access disable [--user U]\n'
    printf '  lsshm access repair [--user U]\n'
    printf '\n'
    lsshm_out 'Local keys (to connect ELSEWHERE):'
    printf '  lsshm key list|generate\n'
    printf '  lsshm key inspect PATH\n'
    printf '  lsshm key export PATH\n'
    printf '  lsshm key delete PATH\n'
    printf '  lsshm key agent list|add PATH|remove PATH\n'
    printf '\n'
    lsshm_out 'Remote hosts:'
    printf '  lsshm host list|add\n'
    printf '  lsshm host edit|delete|test|connect|copy-key|revoke-key NAME\n'
}

# ---------------------------------------------------------------------------
# Installation / uninstallation
# ---------------------------------------------------------------------------
lsshm_path_in_file() {
    local file="$1"
    [ -f "$file" ] && grep -q '.local/bin' "$file" 2>/dev/null
}

lsshm_path_export_line() {
    printf '# Added by LSSHM\nexport PATH="$HOME/.local/bin:$PATH"\n'
}

lsshm_path_is_set() {
    case ":$PATH:" in
        *":$LSSHM_BIN_DIR:"*) return 0 ;;
    esac
    return 1
}

lsshm_path_activate_session() {
    if lsshm_path_is_set; then
        return 0
    fi
    export PATH="$LSSHM_BIN_DIR:$PATH"
    lsshm_ok 'PATH activated for this session.'
}

# Persist ~/.local/bin in the user profile and activate it in the current shell.
# No interactive confirm: called automatically after a successful install.
lsshm_ensure_path() {
    local profile="$LSSHM_HOME/.profile"
    local bashrc="$LSSHM_HOME/.bashrc"
    local wrote=0

    if ! lsshm_path_in_file "$profile"; then
        lsshm_path_export_line >>"$profile"
        wrote=1
        lsshm_ok 'PATH configured in %s for future logins.' "$profile"
    fi

    # Root interactive shell (Debian, Proxmox): ~/.bashrc is often read each session.
    if [ -f "$bashrc" ] && ! lsshm_path_in_file "$bashrc"; then
        lsshm_path_export_line >>"$bashrc"
        wrote=1
        lsshm_ok 'Also added to %s (interactive shell).' "$bashrc"
    fi

    if [ "$wrote" = "0" ] && lsshm_path_in_file "$profile"; then
        lsshm_ok 'PATH already configured in %s.' "$profile"
    fi

    lsshm_path_activate_session
}

# Legacy interactive helper (kept for callers that still ask). Prefer lsshm_ensure_path.
lsshm_check_path() {
    lsshm_path_is_set && return 0
    lsshm_ensure_path
}

lsshm_install() {
    lsshm_header

    # Ask which language to use (preselecting the detected system language) and
    # store the choice so it persists for future runs.
    if lsshm_is_interactive; then
        lsshm_i18n_choose
    fi

    lsshm_info 'Installing LSSHM into the user directory...'
    lsshm_ensure_dirs
    mkdir -p "$LSSHM_DATA_DIR" "$LSSHM_BIN_DIR"

    local self; self="$(lsshm_self_path)"
    if [ -n "$self" ] && [ -f "$self" ]; then
        install -m 0755 "$self" "$LSSHM_INSTALL_TARGET"
    else
        lsshm_info 'Downloading lsshm.sh from the repository...'
        local tmp; tmp="$(lsshm_mktemp)"
        lsshm_download "$LSSHM_REPO_RAW/lsshm.sh" "$tmp" || lsshm_die 'Download failed.'
        bash -n "$tmp" || lsshm_die 'The downloaded script is invalid.'
        lsshm_update_verify_checksum "$tmp" || lsshm_die 'SHA-256 verification failed: installation aborted.'
        install -m 0755 "$tmp" "$LSSHM_INSTALL_TARGET"
    fi

    ln -sf "$LSSHM_INSTALL_TARGET" "$LSSHM_BIN_LINK"
    lsshm_ok 'Installed:'
    printf '  %s\n' "$LSSHM_INSTALL_TARGET"
    printf '  %s -> %s\n' "$LSSHM_BIN_LINK" "$LSSHM_INSTALL_TARGET"

    lsshm_config_write_default
    lsshm_ensure_path
    lsshm_ok 'Installation complete.'
    lsshm_ok 'Run: lsshm'
    lsshm_note 'PATH was updated for future sessions; open a new terminal if the command is not found.'
}

lsshm_uninstall() {
    lsshm_header
    lsshm_warn 'Uninstalling LSSHM.'
    lsshm_confirm "$(lsshm_t 'Continue?')" no || { lsshm_info 'Cancelled.'; return 0; }

    rm -f "$LSSHM_BIN_LINK"
    rm -f "$LSSHM_INSTALL_TARGET" "$LSSHM_INSTALL_TARGET.prev"
    rmdir "$LSSHM_DATA_DIR" 2>/dev/null || true
    lsshm_ok 'Binary and link removed.'

    if lsshm_confirm "$(lsshm_tf 'Also remove configuration and state (%s, %s)?' "$LSSHM_CONFIG_DIR" "$LSSHM_STATE_DIR")" no; then
        rm -rf "$LSSHM_CONFIG_DIR" "$LSSHM_STATE_DIR" "$LSSHM_CACHE_DIR"
        lsshm_ok 'Configuration and state removed.'
    else
        lsshm_info 'Configuration kept: %s' "$LSSHM_CONFIG_DIR"
    fi
    lsshm_info 'Note: LSSHM does not modify your SSH configuration on uninstall.'
    lsshm_info 'Remember to remove the PATH line from ~/.profile if necessary.'
}

# ---------------------------------------------------------------------------
# Sub-command dispatchers
# ---------------------------------------------------------------------------
lsshm_cmd_server() {
    local sub="${1:-status}"; shift || true
    case "$sub" in
        status)  lsshm_server_status ;;
        install) lsshm_server_install ;;
        start)   lsshm_server_start ;;
        stop)    lsshm_server_stop ;;
        restart) lsshm_server_restart ;;
        reload)  lsshm_server_reload ;;
        enable)  lsshm_server_enable ;;
        disable) lsshm_server_disable ;;
        config)  lsshm_server_config_show ;;
        test)    lsshm_server_config_test && lsshm_ok 'Configuration valid.' ;;
        logs)    lsshm_server_logs "${1:-40}" ;;
        *) lsshm_error 'Unknown server subcommand: %s' "$sub"; return 1 ;;
    esac
}

lsshm_cmd_access() {
    local sub="${1:-list}"; shift || true
    local user="$LSSHM_CALLING_USER" rest=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --user) user="${2:-}"; shift 2 || shift ;;
            --user=*) user="${1#*=}"; shift ;;
            *) rest+=("$1"); shift ;;
        esac
    done
    set -- "${rest[@]}"
    case "$sub" in
        list)    lsshm_access_list "$user" ;;
        add)     lsshm_access_add "$user" "${1:-}" ;;
        remove)  lsshm_access_remove "$user" "${1:-}" ;;
        disable) lsshm_access_disable "$user" "${1:-}" ;;
        repair)  lsshm_access_repair "$user" ;;
        *) lsshm_error 'Unknown access subcommand: %s' "$sub"; return 1 ;;
    esac
}

lsshm_cmd_key() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)     lsshm_keys_list ;;
        generate) lsshm_keys_generate ;;
        inspect)  lsshm_keys_inspect "${1:-}" ;;
        export)   lsshm_keys_export "${1:-}" ;;
        delete)   lsshm_keys_delete "${1:-}" ;;
        agent)
            local asub="${1:-list}"; shift || true
            case "$asub" in
                list)   lsshm_agent_list ;;
                add)    lsshm_agent_add "${1:-}" ;;
                remove) lsshm_agent_remove "${1:-}" ;;
                *) lsshm_error 'Unknown agent subcommand: %s' "$asub"; return 1 ;;
            esac
            ;;
        *) lsshm_error 'Unknown key subcommand: %s' "$sub"; return 1 ;;
    esac
}

lsshm_cmd_host() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)      lsshm_hosts_list ;;
        add)       lsshm_hosts_add ;;
        edit)      lsshm_hosts_edit "${1:-}" ;;
        delete)    lsshm_hosts_delete "${1:-}" ;;
        test)      lsshm_hosts_test "${1:-}" ;;
        connect)   lsshm_hosts_connect "${1:-}" ;;
        copy-key)  lsshm_hosts_copy_key "${1:-}" ;;
        revoke-key) lsshm_hosts_revoke_key "${1:-}" ;;
        *) lsshm_error 'Unknown host subcommand: %s' "$sub"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
lsshm_main() {
    # Parse global options; collect the remaining positional arguments.
    local args=() force_ui=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --user) LSSHM_TARGET_USER="${2:-}"; shift 2 || shift ;;
            --user=*) LSSHM_TARGET_USER="${1#*=}"; shift ;;
            --lang|--language) LSSHM_LANG_OVERRIDE="${2:-}"; shift 2 || shift ;;
            --lang=*|--language=*) LSSHM_LANG_OVERRIDE="${1#*=}"; shift ;;
            --ui) force_ui=1; shift ;;
            -y|--yes) LSSHM_ASSUME_YES=1; shift ;;
            --no-color) LSSHM_NO_COLOR=1; shift ;;
            -V|--version) args+=("version"); shift ;;
            -h|--help) args+=("help"); shift ;;
            --) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done ;;
            *) args+=("$1"); shift ;;
        esac
    done

    lsshm_bootstrap
    # Re-init colors in case --no-color was set after init.
    lsshm_init_colors

    local cmd="${args[0]:-menu}"
    if [ "$force_ui" = "1" ]; then
        cmd="ui"
    fi

    # Target-user prompt is only for personal SSH file management — never for
    # install/uninstall/update/help/version (or server-only ops).
    case "$cmd" in
        install|uninstall|update|version|help|--help|-h|server) ;;
        *) lsshm_resolve_target_user ;;
    esac

    # First interactive run without a stored language: offer to choose one
    # (preselecting the detected system language) and remember it.
    # Skip when --lang already forced a language for this invocation.
    case "$cmd" in
        menu|ui)
            if ! lsshm_i18n_configured \
                && [ -z "${LSSHM_LANG_OVERRIDE:-}" ] \
                && lsshm_is_interactive; then
                lsshm_i18n_choose
            fi
            ;;
    esac

    case "$cmd" in
        menu)
            lsshm_update_check || true
            lsshm_cli_main
            ;;
        ui) lsshm_dialog_main ;;
        status) lsshm_status_panel ;;
        doctor) lsshm_doctor ;;
        audit) lsshm_audit ;;
        update)
            case "${args[1]:-}" in
                rollback) lsshm_update_rollback ;;
                *) lsshm_update_run ;;
            esac
            ;;
        install) lsshm_install ;;
        uninstall) lsshm_uninstall ;;
        server) lsshm_cmd_server "${args[@]:1}" ;;
        access) lsshm_cmd_access "${args[@]:1}" ;;
        key)    lsshm_cmd_key "${args[@]:1}" ;;
        host)   lsshm_cmd_host "${args[@]:1}" ;;
        version) printf '%s v%s\n' "$LSSHM_NAME" "$LSSHM_VERSION" ;;
        help|--help|-h) lsshm_usage ;;
        *)
            lsshm_error 'Unknown command: %s' "$cmd"
            lsshm_usage
            return 1
            ;;
    esac
}
