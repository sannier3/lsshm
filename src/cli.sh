# shellcheck shell=bash
# =============================================================================
# cli.sh - dependency-free CLI menus
# =============================================================================

# The status panel shown at the top of the main menu.
# Must not prompt for sudo: uses cached/non-interactive sshd -T or file parse.
lsshm_status_panel() {
    local active port root pass rootkeys userkeys hosts dump
    if lsshm_server_is_installed && lsshm_server_is_active; then active="$(lsshm_t 'active')"; else active="$(lsshm_t 'inactive')"; fi

    # One dump (or none) for all status fields — never three sudo prompts.
    dump="$(lsshm_server_config_dump)" || dump=""
    if [ -n "$dump" ]; then
        port="$(printf '%s\n' "$dump" | awk 'tolower($1)=="port"{sub($1 FS,""); print; exit}')"
        root="$(printf '%s\n' "$dump" | awk 'tolower($1)=="permitrootlogin"{sub($1 FS,""); print; exit}')"
        pass="$(printf '%s\n' "$dump" | awk 'tolower($1)=="passwordauthentication"{sub($1 FS,""); print; exit}')"
    else
        port="$(lsshm_config_parse_value port)"
        root="$(lsshm_config_parse_value permitrootlogin)"
        pass="$(lsshm_config_parse_value passwordauthentication)"
    fi
    port="${port:-22}"
    root="$(lsshm_rootlogin_label "$root")"
    pass="$(lsshm_yesno_label "$pass")"

    rootkeys="$(lsshm_user_key_count root)"
    userkeys="0"
    local kd; kd="$(lsshm_keys_dir)"
    if [ -d "$kd" ]; then
        userkeys="$(find "$kd" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null | wc -l | tr -d ' ')"
    fi
    hosts="$(lsshm_hosts_count)"

    lsshm_out 'Managed user: %s' "$LSSHM_CALLING_USER"
    lsshm_out 'SSH server status: %s' "$active"
    lsshm_out 'Port: %s' "$port"
    lsshm_out 'Root access: %s' "$root"
    lsshm_out 'Password authentication: %s' "$pass"
    lsshm_out 'Authorized keys for root: %s' "$rootkeys"
    lsshm_out 'Private keys of %s: %s' "$LSSHM_CALLING_USER" "$userkeys"
    lsshm_out 'Registered remote hosts: %s' "$hosts"
}

lsshm_cli_main() {
    lsshm_require_interactive
    while true; do
        clear 2>/dev/null || true
        lsshm_header
        lsshm_menu_try lsshm_status_panel
        printf '\n'
        lsshm_out '1. Manage the local SSH server'
        lsshm_out '2. Manage access to this machine'
        lsshm_out '3. Manage my SSH keys'
        lsshm_out '4. Manage remote hosts'
        lsshm_out '5. View connections and logs'
        lsshm_out '6. Run a security audit'
        lsshm_out '7. Back up or restore'
        lsshm_out '8. LSSHM settings'
        lsshm_out '9. Quit'
        local choice=""
        choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '9' || true)"
        case "$choice" in
            1) lsshm_menu_try lsshm_cli_server_menu ;;
            2) lsshm_menu_try lsshm_cli_access_menu ;;
            3) lsshm_menu_try lsshm_cli_keys_menu ;;
            4) lsshm_menu_try lsshm_cli_hosts_menu ;;
            5) lsshm_menu_try lsshm_logs_menu ;;
            6) lsshm_menu_action lsshm_audit ;;
            7) lsshm_menu_try lsshm_backup_menu ;;
            8) lsshm_menu_try lsshm_settings_menu ;;
            9|q|Q) break ;;
            *) lsshm_warn 'Invalid choice.' ; lsshm_pause ;;
        esac
    done
}

# --- server menu -------------------------------------------------------------

lsshm_cli_server_menu() {
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_server_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'Local SSH server'
            printf '\n'
            lsshm_menu_try lsshm_server_status
            printf '\n'
            printf ' 1. %s\n' "$(lsshm_t 'Install OpenSSH Server')"
            printf ' 2. %s\n' "$(lsshm_t 'Start the service')"
            printf ' 3. %s\n' "$(lsshm_t 'Stop the service')"
            printf ' 4. %s\n' "$(lsshm_t 'Restart the service')"
            printf ' 5. %s\n' "$(lsshm_t 'Reload the service')"
            printf ' 6. %s\n' "$(lsshm_t 'Enable at boot')"
            printf ' 7. %s\n' "$(lsshm_t 'Disable at boot')"
            printf ' 8. %s\n' "$(lsshm_t 'Change the port')"
            printf ' 9. %s\n' "$(lsshm_t 'Manage root access')"
            printf '10. %s\n' "$(lsshm_t 'Password authentication')"
            printf '11. %s\n' "$(lsshm_t 'Key authentication')"
            printf '12. %s\n' "$(lsshm_t 'Allowed users (AllowUsers)')"
            printf '13. %s\n' "$(lsshm_t 'Allowed groups (AllowGroups)')"
            printf '14. %s\n' "$(lsshm_t 'Test the configuration (sshd -t)')"
            printf '15. %s\n' "$(lsshm_t 'Show the effective configuration (sshd -T)')"
            printf '16. %s\n' "$(lsshm_t 'View the logs')"
            printf '17. %s\n' "$(lsshm_t 'Back')"
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '17' || true)"
        fi
        case "$choice" in
            1)  lsshm_ui_run "$(lsshm_t 'OpenSSH Server installation')" lsshm_server_install ;;
            2)  lsshm_ui_run "$(lsshm_t 'Starting SSH')" lsshm_server_start ;;
            3)  lsshm_ui_run "$(lsshm_t 'Stopping SSH')" lsshm_server_stop ;;
            4)  lsshm_ui_run "$(lsshm_t 'Restarting SSH')" lsshm_server_restart ;;
            5)  lsshm_ui_run "$(lsshm_t 'Reloading SSH')" lsshm_server_reload ;;
            6)  lsshm_ui_run "$(lsshm_t 'Enabling at boot')" lsshm_server_enable ;;
            7)  lsshm_ui_run "$(lsshm_t 'Disabling at boot')" lsshm_server_disable ;;
            8)  lsshm_menu_action lsshm_set_port ;;
            9)  lsshm_menu_action lsshm_set_root_login ;;
            10) lsshm_menu_action lsshm_set_password_auth ;;
            11) lsshm_menu_action lsshm_set_pubkey_auth ;;
            12) lsshm_menu_action lsshm_set_allow_users ;;
            13) lsshm_menu_action lsshm_set_allow_groups ;;
            14) lsshm_ui_run "$(lsshm_t 'sshd -t test')" lsshm_server_config_test ;;
            15)
                if lsshm_uses_dialog_ui; then
                    lsshm_menu_try lsshm_ui_show "$(lsshm_t 'Effective configuration')" lsshm_server_config_show
                else
                    lsshm_server_config_show | ${PAGER:-less} 2>/dev/null || lsshm_menu_try lsshm_server_config_show
                    lsshm_pause
                fi
                ;;
            16) lsshm_ui_run "$(lsshm_t 'SSH logs')" lsshm_server_logs ;;
            17|q|Q) break ;;
            *)  lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}

# --- access menu (incoming) --------------------------------------------------

lsshm_cli_access_menu() {
    while true; do
        local user="$LSSHM_CALLING_USER"
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_access_menu "$user")" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'Access to this machine (keys allowed to connect HERE)'
            lsshm_out 'Target user: %s' "$user"
            printf '\n'
            printf '1. %s\n' "$(lsshm_t 'List users')"
            printf '2. %s\n' "$(lsshm_t 'List authorized keys')"
            printf '3. %s\n' "$(lsshm_t 'Add a key (paste or import a .pub)')"
            printf '4. %s\n' "$(lsshm_t 'Remove a key')"
            printf '5. %s\n' "$(lsshm_t 'Disable / re-enable a key')"
            printf '6. %s\n' "$(lsshm_t 'Repair ~/.ssh permissions')"
            printf '7. %s\n' "$(lsshm_t 'Detect duplicates')"
            printf '8. %s\n' "$(lsshm_t 'Change target user')"
            printf '9. %s\n' "$(lsshm_t 'Back')"
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '9' || true)"
        fi
        case "$choice" in
            1) lsshm_ui_run "$(lsshm_t 'Local users')" lsshm_users_print ;;
            2) lsshm_ui_run "$(lsshm_t 'Authorized keys')" lsshm_access_list "$user" ;;
            3) lsshm_menu_action lsshm_access_add "$user" ;;
            4) lsshm_menu_action lsshm_access_remove "$user" ;;
            5) lsshm_menu_action lsshm_access_disable "$user" ;;
            6) lsshm_ui_run "$(lsshm_t 'Permission repair')" lsshm_access_repair "$user" ;;
            7) lsshm_ui_run "$(lsshm_t 'Duplicates')" lsshm_access_duplicates "$user" ;;
            8) lsshm_menu_action lsshm_pick_target_user "$user" ;;
            9|q|Q) break ;;
            *) lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}

# --- local keys menu (outgoing) ----------------------------------------------

lsshm_cli_keys_menu() {
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_keys_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'SSH keys of %s (to connect ELSEWHERE)' "$LSSHM_CALLING_USER"
            lsshm_out 'Directory: %s' "$(lsshm_keys_dir)"
            printf '\n'
            printf '1. %s\n'  "$(lsshm_t 'List key pairs')"
            printf '2. %s\n'  "$(lsshm_t 'Generate a new key (ED25519 by default)')"
            printf '3. %s\n'  "$(lsshm_t 'Inspect a key')"
            printf '4. %s\n'  "$(lsshm_t 'Show / export a public key')"
            printf '5. %s\n'  "$(lsshm_t 'Change the passphrase')"
            printf '6. %s\n'  "$(lsshm_t 'Delete a key pair')"
            printf '7. %s\n'  "$(lsshm_t 'ssh-agent: list')"
            printf '8. %s\n'  "$(lsshm_t 'ssh-agent: add a key')"
            printf '9. %s\n'  "$(lsshm_t 'ssh-agent: remove a key')"
            printf '10. %s\n' "$(lsshm_t 'Change target user')"
            printf '11. %s\n' "$(lsshm_t 'Back')"
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '11' || true)"
        fi
        case "$choice" in
            1)  lsshm_ui_run "$(lsshm_t 'Key pairs')" lsshm_keys_list ;;
            2)  lsshm_menu_action lsshm_keys_generate ;;
            3)  lsshm_menu_action lsshm_keys_inspect "" ;;
            4)  lsshm_ui_run "$(lsshm_t 'Public key')" lsshm_keys_export "" ;;
            5)  lsshm_menu_action lsshm_keys_passphrase "" ;;
            6)  lsshm_menu_action lsshm_keys_delete "" ;;
            7)  lsshm_ui_run "ssh-agent" lsshm_agent_list ;;
            8)  lsshm_menu_action lsshm_agent_add "" ;;
            9)  lsshm_menu_action lsshm_agent_remove "" ;;
            10) lsshm_menu_action lsshm_pick_target_user "$LSSHM_CALLING_USER" ;;
            11|q|Q) break ;;
            *)  lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}

# --- remote hosts menu -------------------------------------------------------

lsshm_cli_hosts_menu() {
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_hosts_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'Remote hosts (~/.ssh/config) - optional'
            lsshm_out 'User: %s' "$LSSHM_CALLING_USER"
            printf '\n'
            printf ' 1. %s\n' "$(lsshm_t 'List hosts')"
            printf ' 2. %s\n' "$(lsshm_t 'Add a host')"
            printf ' 3. %s\n' "$(lsshm_t 'Edit a host')"
            printf ' 4. %s\n' "$(lsshm_t 'Delete a host')"
            printf ' 5. %s\n' "$(lsshm_t 'Test a host (resolution, port, auth)')"
            printf ' 6. %s\n' "$(lsshm_t 'Effective configuration (ssh -G)')"
            printf ' 7. %s\n' "$(lsshm_t 'Connect to a host')"
            printf ' 8. %s\n' "$(lsshm_t 'Copy a key (ssh-copy-id)')"
            printf ' 9. %s\n' "$(lsshm_t 'Revoke a remote key')"
            printf '10. %s\n' "$(lsshm_t 'known_hosts: list')"
            printf '11. %s\n' "$(lsshm_t 'known_hosts: remove a fingerprint')"
            printf '12. %s\n' "$(lsshm_t 'Back')"
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '12' || true)"
        fi
        case "$choice" in
            1)  lsshm_ui_run "$(lsshm_t 'Remote hosts')" lsshm_hosts_list ;;
            2)  lsshm_menu_action lsshm_hosts_add ;;
            3)  lsshm_menu_action lsshm_hosts_edit "" ;;
            4)  lsshm_menu_action lsshm_hosts_delete "" ;;
            5)  lsshm_ui_run "$(lsshm_t 'Host test')" lsshm_hosts_test "" ;;
            6)  lsshm_ui_run "$(lsshm_t 'Effective configuration')" lsshm_hosts_effective "" ;;
            7)  lsshm_menu_try lsshm_hosts_connect "" ;;
            8)  lsshm_menu_action lsshm_hosts_copy_key "" ;;
            9)  lsshm_menu_action lsshm_hosts_revoke_key "" ;;
            10) lsshm_ui_run "known_hosts" lsshm_known_hosts_list ;;
            11) lsshm_menu_action lsshm_known_hosts_remove "" ;;
            12|q|Q) break ;;
            *)  lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}

# --- settings ----------------------------------------------------------------

lsshm_settings_menu() {
    lsshm_config_load
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_settings_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'LSSHM settings'
            printf '\n'
            lsshm_out 'Managed user        : %s' "$LSSHM_CALLING_USER"
            lsshm_out 'Update check        : %s' "$LSSHM_CFG_UPDATE_CHECK"
            lsshm_out 'Update channel      : %s' "$LSSHM_CFG_UPDATE_CHANNEL"
            lsshm_out 'Language            : %s' "$(lsshm_lang_native_name "$LSSHM_LANG")"
            lsshm_out 'Configuration file  : %s' "$LSSHM_CONFIG_FILE"
            printf '\n'
            lsshm_out '1. Update check: always'
            lsshm_out '2. Update check: once a day'
            lsshm_out '3. Update check: never'
            lsshm_out '4. Check for updates now'
            lsshm_out '5. Show diagnostics (doctor)'
            lsshm_out '6. Change the language'
            lsshm_out '7. Change managed user'
            lsshm_out '8. Back'
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '8' || true)"
        fi
        case "$choice" in
            1) lsshm_menu_try lsshm_config_set update_check always; lsshm_menu_try lsshm_config_load ;;
            2) lsshm_menu_try lsshm_config_set update_check daily; lsshm_menu_try lsshm_config_load ;;
            3) lsshm_menu_try lsshm_config_set update_check never; lsshm_menu_try lsshm_config_load ;;
            4) LSSHM_CFG_UPDATE_CHECK=always lsshm_menu_action lsshm_update_run ;;
            5) lsshm_ui_run "$(lsshm_t 'LSSHM diagnostics')" lsshm_doctor ;;
            6) lsshm_menu_action lsshm_i18n_choose; lsshm_menu_try lsshm_config_load ;;
            7) lsshm_menu_action lsshm_pick_target_user "$LSSHM_CALLING_USER" ;;
            8|q|Q) break ;;
            *) lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}
