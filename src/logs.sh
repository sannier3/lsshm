# shellcheck shell=bash
# =============================================================================
# logs.sh - sessions, logins, and SSH service logs
# =============================================================================

lsshm_logs_sessions() {
    lsshm_info 'Active SSH sessions:'
    if lsshm_have who; then
        who 2>/dev/null | grep -Ei 'pts|ssh' || who 2>/dev/null || lsshm_info '  (none)'
    else
        lsshm_warn "'who' unavailable."
    fi
}

lsshm_logs_recent_logins() {
    lsshm_info 'Recent logins:'
    if lsshm_have last; then
        lsshm_run_privileged last -n 10 2>/dev/null | head -n 10 || true
    else
        lsshm_warn "'last' unavailable."
    fi
}

lsshm_logs_failed() {
    lsshm_info 'Recent failed login attempts:'
    if lsshm_have lastb; then
        lsshm_run_privileged lastb -n 10 2>/dev/null | head -n 10 || lsshm_info '  (none or not accessible)'
    elif [ -f /var/log/auth.log ]; then
        lsshm_run_privileged grep -i 'failed password' /var/log/auth.log 2>/dev/null | tail -n 10 || lsshm_info '  (none)'
    else
        lsshm_warn 'No source of failed attempts available.'
    fi
}

lsshm_logs_service() {
    lsshm_info 'SSH service logs:'
    lsshm_server_logs 40
}

lsshm_logs_menu() {
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_logs_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'Connections and logs'
            printf '\n'
            lsshm_out '  1. Active sessions'
            lsshm_out '  2. Recent logins'
            lsshm_out '  3. Failed attempts'
            lsshm_out '  4. SSH service logs'
            lsshm_out '  5. Back'
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '5' || true)"
        fi
        case "$choice" in
            1) lsshm_ui_run "$(lsshm_t 'Active sessions')" lsshm_logs_sessions ;;
            2) lsshm_ui_run "$(lsshm_t 'Recent logins')" lsshm_logs_recent_logins ;;
            3) lsshm_ui_run "$(lsshm_t 'Failed attempts')" lsshm_logs_failed ;;
            4) lsshm_ui_run "$(lsshm_t 'SSH service logs')" lsshm_logs_service ;;
            5|q|Q) break ;;
            *) lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}
