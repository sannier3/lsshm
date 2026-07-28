# shellcheck shell=bash
# =============================================================================
# dialog.sh - optional terminal user interface using `dialog`
# =============================================================================

lsshm_dialog_available() { lsshm_have dialog; }

# dialog --menu wrapper. Prints the selected tag or returns non-zero on cancel.
lsshm_ui_menu() {
    local title="$1" body="$2"
    shift 2
    lsshm_tty_restore
    local result ret
    result="$(dialog --clear --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
        --title "$title" --menu "$body" 22 74 14 "$@" \
        3>&1 1>&2 2>&3)"
    ret=$?
    case "$ret" in
        0)
            [ -n "$result" ] || return 1
            printf '%s' "$result"
            return 0
            ;;
        *) return 1 ;;
    esac
}

# Run a command and show stdout/stderr inside dialog.
lsshm_ui_show() {
    local title="$1"; shift
    local tmp; tmp="$(lsshm_mktemp)"
    (
        export LSSHM_NO_COLOR=1
        export LSSHM_C_RESET="" LSSHM_C_BOLD="" LSSHM_C_DIM=""
        export LSSHM_C_RED="" LSSHM_C_GREEN="" LSSHM_C_YELLOW=""
        "$@"
    ) >"$tmp" 2>&1 || true
    lsshm_strip_ansi_file "$tmp"
    lsshm_tty_restore
    if [ ! -s "$tmp" ]; then
        dialog --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
            --title "$title" --msgbox "$(lsshm_t '(no output)')" 8 50
        return 0
    fi
    dialog --clear --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
        --title "$title" --programbox "$(lsshm_t 'Result')" 22 74 0 <"$tmp" \
        2>/dev/null || {
            local text; text="$(head -c 4000 "$tmp")"
            dialog --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
                --title "$title" --msgbox "$text" 22 74
        }
}

lsshm_ui_run() {
    local title="$1"; shift
    # Always return success: a cancelled/failed action must not exit the menu (set -e).
    if lsshm_uses_dialog_ui; then
        lsshm_ui_show "$title" "$@" || true
    else
        "$@" || true
        lsshm_pause
    fi
    return 0
}

# Offer to install dialog when missing.
lsshm_dialog_offer_install() {
    lsshm_out 'The terminal GUI requires the dialog package.'
    printf '\n'
    lsshm_out '1. Install dialog'
    lsshm_out '2. Continue with the CLI interface'
    lsshm_out '3. Cancel'
    printf '\n'
    local choice; choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '2')"
    case "$choice" in
        1)
            lsshm_dialog_install
            if lsshm_dialog_available; then
                return 0
            fi
            lsshm_warn 'dialog could not be installed. Falling back to the CLI interface.'
            return 1
            ;;
        2) return 1 ;;
        *) exit 0 ;;
    esac
}

lsshm_dialog_install() {
    lsshm_require_root
    case "$LSSHM_PKG_MGR" in
        apt)    lsshm_run_privileged apt-get update && lsshm_run_privileged apt-get install -y dialog ;;
        apk)    lsshm_run_privileged apk add dialog ;;
        dnf)    lsshm_run_privileged dnf install -y dialog ;;
        yum)    lsshm_run_privileged yum install -y dialog ;;
        pacman) lsshm_run_privileged pacman -Sy --noconfirm dialog ;;
        zypper) lsshm_run_privileged zypper install -y dialog ;;
        *)      lsshm_error 'Unsupported package manager: %s' "$LSSHM_PKG_MGR" ;;
    esac
}

# Entry point for `lsshm ui`. Falls back to CLI when dialog is unavailable.
lsshm_dialog_main() {
    lsshm_require_interactive
    if ! lsshm_dialog_available; then
        if ! lsshm_dialog_offer_install; then
            lsshm_cli_main
            return
        fi
    fi
    LSSHM_UI_MODE=1
    export LSSHM_UI_MODE
    lsshm_init_colors
    # Preserve temp-file cleanup from main; do not replace it entirely.
    trap 'LSSHM_UI_MODE=0; lsshm_init_colors; lsshm_tty_restore; lsshm_cleanup' EXIT INT TERM
    lsshm_dialog_menu_loop
    LSSHM_UI_MODE=0
    lsshm_init_colors
    lsshm_tty_restore
    trap lsshm_cleanup EXIT INT TERM
}

lsshm_dialog_status_text() {
    lsshm_status_panel
}

lsshm_dialog_menu_loop() {
    while true; do
        local choice ret=0
        choice="$(lsshm_ui_menu "$(lsshm_t 'Main menu')" "$(lsshm_dialog_status_text)" \
            1 "$(lsshm_t 'Manage the local SSH server')" \
            2 "$(lsshm_t 'Manage access to this machine')" \
            3 "$(lsshm_t 'Manage my SSH keys')" \
            4 "$(lsshm_t 'Manage remote hosts')" \
            5 "$(lsshm_t 'View connections and logs')" \
            6 "$(lsshm_t 'Run a security audit')" \
            7 "$(lsshm_t 'Back up or restore')" \
            8 "$(lsshm_t 'LSSHM settings')" \
            9 "$(lsshm_t 'Quit')")" || ret=$?

        [ "$ret" -ne 0 ] && break
        case "$choice" in
            1) lsshm_menu_try lsshm_cli_server_menu ;;
            2) lsshm_menu_try lsshm_cli_access_menu ;;
            3) lsshm_menu_try lsshm_cli_keys_menu ;;
            4) lsshm_menu_try lsshm_cli_hosts_menu ;;
            5) lsshm_menu_try lsshm_logs_menu ;;
            6) lsshm_ui_run "$(lsshm_t 'Security audit')" lsshm_audit ;;
            7) lsshm_menu_try lsshm_backup_menu ;;
            8) lsshm_menu_try lsshm_settings_menu ;;
            9) break ;;
        esac
    done
    lsshm_tty_restore
}

# --- dialog sub-menus (used when LSSHM_UI_MODE=1) ---------------------------

lsshm_dialog_server_menu() {
    local body
    body="$(lsshm_server_status 2>/dev/null)"
    lsshm_ui_menu "$(lsshm_t 'Local SSH server')" "$body" \
        1 "$(lsshm_t 'Install OpenSSH Server')" \
        2 "$(lsshm_t 'Start the service')" \
        3 "$(lsshm_t 'Stop the service')" \
        4 "$(lsshm_t 'Restart the service')" \
        5 "$(lsshm_t 'Reload the service')" \
        6 "$(lsshm_t 'Enable at boot')" \
        7 "$(lsshm_t 'Disable at boot')" \
        8 "$(lsshm_t 'Change the port')" \
        9 "$(lsshm_t 'Address family (AddressFamily)')" \
        10 "$(lsshm_t 'Listen addresses (ListenAddress)')" \
        11 "$(lsshm_t 'Manage root access')" \
        12 "$(lsshm_t 'Password authentication')" \
        13 "$(lsshm_t 'Key authentication')" \
        14 "$(lsshm_t 'Allowed users (AllowUsers)')" \
        15 "$(lsshm_t 'Allowed groups (AllowGroups)')" \
        16 "$(lsshm_t 'Test the configuration (sshd -t)')" \
        17 "$(lsshm_t 'Show the effective configuration (sshd -T)')" \
        18 "$(lsshm_t 'View the logs')" \
        19 "$(lsshm_t 'Back')"
}

lsshm_dialog_access_menu() {
    local user="$1" body
    body="$(lsshm_t 'Access to this machine (keys allowed to connect HERE)')
$(lsshm_tf 'Target user: %s' "$user")"
    lsshm_ui_menu "$(lsshm_t 'Manage access to this machine')" "$body" \
        1 "$(lsshm_t 'List users')" \
        2 "$(lsshm_t 'List authorized keys')" \
        3 "$(lsshm_t 'Add a key (paste or import a .pub)')" \
        4 "$(lsshm_t 'Remove a key')" \
        5 "$(lsshm_t 'Disable / re-enable a key')" \
        6 "$(lsshm_t 'Repair ~/.ssh permissions')" \
        7 "$(lsshm_t 'Detect duplicates')" \
        8 "$(lsshm_t 'Change target user')" \
        9 "$(lsshm_t 'Back')"
}

lsshm_dialog_keys_menu() {
    lsshm_ui_menu "$(lsshm_t 'Manage my SSH keys')" "$(lsshm_tf 'SSH keys of %s (to connect ELSEWHERE)' "$LSSHM_CALLING_USER")" \
        1 "$(lsshm_t 'List key pairs')" \
        2 "$(lsshm_t 'Generate a new key (ED25519 by default)')" \
        3 "$(lsshm_t 'Inspect a key')" \
        4 "$(lsshm_t 'Show / export a public key')" \
        5 "$(lsshm_t 'Change the passphrase')" \
        6 "$(lsshm_t 'Delete a key pair')" \
        7 "$(lsshm_t 'ssh-agent: list')" \
        8 "$(lsshm_t 'ssh-agent: add a key')" \
        9 "$(lsshm_t 'ssh-agent: remove a key')" \
        10 "$(lsshm_t 'Change target user')" \
        11 "$(lsshm_t 'Back')"
}

lsshm_dialog_hosts_menu() {
    lsshm_ui_menu "$(lsshm_t 'Remote hosts')" "$(lsshm_t 'Remote hosts (~/.ssh/config) - optional')" \
        1 "$(lsshm_t 'List hosts')" \
        2 "$(lsshm_t 'Add a host')" \
        3 "$(lsshm_t 'Edit a host')" \
        4 "$(lsshm_t 'Delete a host')" \
        5 "$(lsshm_t 'Test a host (resolution, port, auth)')" \
        6 "$(lsshm_t 'Effective configuration (ssh -G)')" \
        7 "$(lsshm_t 'Connect to a host')" \
        8 "$(lsshm_t 'Copy a key (ssh-copy-id)')" \
        9 "$(lsshm_t 'Revoke a remote key')" \
        10 "$(lsshm_t 'known_hosts: list')" \
        11 "$(lsshm_t 'known_hosts: remove a fingerprint')" \
        12 "$(lsshm_t 'Back')"
}

lsshm_dialog_settings_menu() {
    lsshm_config_load
    local body
    body="$(lsshm_tf 'Managed user        : %s' "$LSSHM_CALLING_USER")
$(lsshm_tf 'Update check        : %s' "$LSSHM_CFG_UPDATE_CHECK")
$(lsshm_tf 'Update channel      : %s' "$LSSHM_CFG_UPDATE_CHANNEL")
$(lsshm_tf 'Language            : %s' "$(lsshm_lang_native_name "$LSSHM_LANG")")
$(lsshm_tf 'Configuration file  : %s' "$LSSHM_CONFIG_FILE")"
    lsshm_ui_menu "$(lsshm_t 'LSSHM settings')" "$body" \
        1 "$(lsshm_t 'Update check: always')" \
        2 "$(lsshm_t 'Update check: once a day')" \
        3 "$(lsshm_t 'Update check: never')" \
        4 "$(lsshm_t 'Check for updates now')" \
        5 "$(lsshm_t 'Show diagnostics (doctor)')" \
        6 "$(lsshm_t 'Change the language')" \
        7 "$(lsshm_t 'Change managed user')" \
        8 "$(lsshm_t 'Back')"
}

lsshm_dialog_logs_menu() {
    lsshm_ui_menu "$(lsshm_t 'Connections and logs')" "$(lsshm_t 'Consult SSH activity')" \
        1 "$(lsshm_t 'Active sessions')" \
        2 "$(lsshm_t 'Recent logins')" \
        3 "$(lsshm_t 'Failed attempts')" \
        4 "$(lsshm_t 'SSH service logs')" \
        5 "$(lsshm_t 'Back')"
}

lsshm_dialog_backup_menu() {
    lsshm_ui_menu "$(lsshm_t 'Backup and restore')" "$(lsshm_t 'Back up or restore the SSH configuration')" \
        1 "$(lsshm_t 'Back up the SSH server configuration')" \
        2 "$(lsshm_t 'Back up authorized keys (authorized_keys)')" \
        3 "$(lsshm_t 'List backups')" \
        4 "$(lsshm_t 'Restore a server configuration')" \
        5 "$(lsshm_t 'Back')"
}
