# shellcheck shell=bash
# =============================================================================
# server.sh - OpenSSH server service management
# =============================================================================

lsshm_server_is_installed() {
    [ -n "${LSSHM_SSHD_BIN:-}" ] && [ -x "$LSSHM_SSHD_BIN" ]
}

# --- service actions ---------------------------------------------------------

lsshm_server_action() {
    # lsshm_server_action start|stop|restart|reload|enable|disable
    local action="$1"
    case "$LSSHM_SVC_MGR" in
        systemd)
            lsshm_run_privileged systemctl "$action" "$LSSHM_SSH_SERVICE"
            ;;
        openrc)
            case "$action" in
                enable)  lsshm_run_privileged rc-update add "$LSSHM_SSH_SERVICE" default ;;
                disable) lsshm_run_privileged rc-update del "$LSSHM_SSH_SERVICE" default ;;
                reload)  lsshm_run_privileged rc-service "$LSSHM_SSH_SERVICE" reload \
                             || lsshm_run_privileged rc-service "$LSSHM_SSH_SERVICE" restart ;;
                *)       lsshm_run_privileged rc-service "$LSSHM_SSH_SERVICE" "$action" ;;
            esac
            ;;
        sysv)
            case "$action" in
                enable|disable)
                    lsshm_warn 'Automatic enable/disable is not handled for SysV here.'
                    return 1 ;;
                *) lsshm_run_privileged service "$LSSHM_SSH_SERVICE" "$action" ;;
            esac
            ;;
        *)
            lsshm_error "Unknown service manager: cannot run '%s'." "$action"
            return 1
            ;;
    esac
}

lsshm_server_start()   { lsshm_server_action start   && lsshm_ok 'SSH service started.'; }
lsshm_server_stop()    { lsshm_server_action stop    && lsshm_ok 'SSH service stopped.'; }
lsshm_server_restart() { lsshm_server_action restart && lsshm_ok 'SSH service restarted.'; }
lsshm_server_enable()  { lsshm_server_action enable  && lsshm_ok 'Automatic startup enabled.'; }
lsshm_server_disable() { lsshm_server_action disable && lsshm_ok 'Automatic startup disabled.'; }

# Reload preferred over restart; validate config first.
lsshm_server_reload() {
    if ! lsshm_server_config_test; then
        lsshm_error 'Invalid configuration: reload cancelled.'
        return 1
    fi
    if lsshm_server_action reload; then
        lsshm_server_config_invalidate_cache
        lsshm_ok 'SSH service reloaded.'
    else
        return 1
    fi
}

# --- status ------------------------------------------------------------------

lsshm_server_is_active() {
    case "$LSSHM_SVC_MGR" in
        systemd) systemctl is-active --quiet "$LSSHM_SSH_SERVICE" ;;
        openrc)  rc-service "$LSSHM_SSH_SERVICE" status >/dev/null 2>&1 ;;
        sysv)    service "$LSSHM_SSH_SERVICE" status >/dev/null 2>&1 ;;
        *)       lsshm_server_port_listening ;;
    esac
}

lsshm_server_is_enabled() {
    case "$LSSHM_SVC_MGR" in
        systemd) systemctl is-enabled --quiet "$LSSHM_SSH_SERVICE" 2>/dev/null ;;
        openrc)  rc-update show default 2>/dev/null | grep -qw "$LSSHM_SSH_SERVICE" ;;
        *)       return 1 ;;
    esac
}

# Is the configured SSH port actually listening?
lsshm_server_port_listening() {
    local port; port="$(lsshm_server_config_effective_value port)"
    port="${port:-22}"
    if lsshm_have ss; then
        ss -ltn 2>/dev/null | grep -Eq "[:.]${port}[[:space:]]"
    elif lsshm_have netstat; then
        netstat -ltn 2>/dev/null | grep -Eq "[:.]${port}[[:space:]]"
    else
        return 2
    fi
}

lsshm_server_status() {
    if ! lsshm_server_is_installed; then
        lsshm_warn 'OpenSSH Server is not installed (sshd binary not found).'
        return 0
    fi
    local active enabled port rootlogin passauth pubkey family listen
    if lsshm_server_is_active; then active="$(lsshm_t active)"; else active="$(lsshm_t inactive)"; fi
    if lsshm_server_is_enabled; then enabled="$(lsshm_t yes)"; else enabled="$(lsshm_t no)"; fi
    port="$(lsshm_server_config_effective_value port)"; port="${port:-22}"
    rootlogin="$(lsshm_server_config_effective_value permitrootlogin)"
    passauth="$(lsshm_server_config_effective_value passwordauthentication)"
    pubkey="$(lsshm_server_config_effective_value pubkeyauthentication)"
    family="$(lsshm_server_config_effective_value addressfamily)"; family="${family:-any}"
    listen="$(lsshm_server_config_effective_values listenaddress | tr '\n' ' ')"
    listen="$(printf '%s' "$listen" | sed 's/[[:space:]]*$//')"
    [ -n "$listen" ] || listen="0.0.0.0 ::"

    lsshm_out 'SSH server status : %s' "$active"
    lsshm_out 'Auto-start        : %s' "$enabled"
    lsshm_out 'Port              : %s' "$port"
    lsshm_out 'Address family    : %s' "$family"
    lsshm_out 'Listen addresses  : %s' "$listen"
    lsshm_out 'Root access       : %s' "$(lsshm_rootlogin_label "$rootlogin")"
    lsshm_out 'Password auth.    : %s' "$(lsshm_yesno_label "$passauth")"
    lsshm_out 'Key auth.         : %s' "$(lsshm_yesno_label "$pubkey")"
}

# --- installation ------------------------------------------------------------

lsshm_server_install() {
    if lsshm_server_is_installed; then
        lsshm_ok 'OpenSSH Server is already installed: %s' "$LSSHM_SSHD_BIN"
        return 0
    fi
    lsshm_info 'Installing OpenSSH Server...'
    lsshm_require_root
    case "$LSSHM_PKG_MGR" in
        apt)
            lsshm_run_privileged apt-get update && \
            lsshm_run_privileged apt-get install -y openssh-server ;;
        apk)
            lsshm_run_privileged apk add openssh ;;
        dnf)
            lsshm_run_privileged dnf install -y openssh-server ;;
        yum)
            lsshm_run_privileged yum install -y openssh-server ;;
        pacman)
            lsshm_run_privileged pacman -Sy --noconfirm openssh ;;
        zypper)
            lsshm_run_privileged zypper install -y openssh ;;
        *)
            lsshm_error 'Unsupported package manager: %s' "$LSSHM_PKG_MGR"
            return 1 ;;
    esac
    # Refresh detection.
    LSSHM_SSHD_BIN="$(lsshm_detect_sshd_bin)"
    if lsshm_server_is_installed; then
        lsshm_ok 'OpenSSH Server installed.'
        lsshm_server_action enable || true
        lsshm_server_action start  || true
    else
        lsshm_error 'The installation appears to have failed.'
        return 1
    fi
}

lsshm_server_logs() {
    local lines="${1:-40}"
    if [ "$LSSHM_SVC_MGR" = "systemd" ] && lsshm_have journalctl; then
        lsshm_run_privileged journalctl -u "$LSSHM_SSH_SERVICE" -n "$lines" --no-pager
    elif [ -f /var/log/auth.log ]; then
        lsshm_run_privileged tail -n "$lines" /var/log/auth.log
    elif [ -f /var/log/secure ]; then
        lsshm_run_privileged tail -n "$lines" /var/log/secure
    else
        lsshm_warn 'No SSH log source detected.'
        return 1
    fi
}
