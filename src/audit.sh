# shellcheck shell=bash
# =============================================================================
# audit.sh - local SSH security audit and diagnostics
# =============================================================================

LSSHM_AUDIT_PASS=0
LSSHM_AUDIT_WARN=0
LSSHM_AUDIT_FAIL=0

lsshm_audit_pass() { LSSHM_AUDIT_PASS=$((LSSHM_AUDIT_PASS+1)); printf '  [%sOK%s]   %s\n' "${LSSHM_C_GREEN:-}" "${LSSHM_C_RESET:-}" "$*"; }
lsshm_audit_warn() { LSSHM_AUDIT_WARN=$((LSSHM_AUDIT_WARN+1)); printf '  [%s%s%s] %s\n' "${LSSHM_C_YELLOW:-}" "$(lsshm_t 'WARN')" "${LSSHM_C_RESET:-}" "$*"; }
lsshm_audit_fail() { LSSHM_AUDIT_FAIL=$((LSSHM_AUDIT_FAIL+1)); printf '  [%s%s%s] %s\n' "${LSSHM_C_RED:-}" "$(lsshm_t 'FAIL')" "${LSSHM_C_RESET:-}" "$*"; }

lsshm_audit() {
    LSSHM_AUDIT_PASS=0; LSSHM_AUDIT_WARN=0; LSSHM_AUDIT_FAIL=0
    lsshm_header
    lsshm_out 'Local SSH security audit'
    printf '\n'

    printf '%s%s%s\n' "${LSSHM_C_BOLD:-}" "$(lsshm_t 'SSH server')" "${LSSHM_C_RESET:-}"
    if lsshm_server_is_installed; then
        lsshm_audit_pass "$(lsshm_t 'OpenSSH Server installed.')"
    else
        lsshm_audit_warn "$(lsshm_t 'OpenSSH Server not installed.')"
    fi

    local root pass maxauth
    root="$(lsshm_server_config_effective_value permitrootlogin)"
    case "$root" in
        no) lsshm_audit_pass "$(lsshm_t 'PermitRootLogin = no (root forbidden).')" ;;
        prohibit-password|without-password) lsshm_audit_pass "$(lsshm_t 'PermitRootLogin = key only.')" ;;
        yes) lsshm_audit_fail "$(lsshm_t 'PermitRootLogin = yes (root with password allowed).')" ;;
        *) lsshm_audit_warn "$(lsshm_tf 'PermitRootLogin = %s.' "${root:-$(lsshm_t 'not set')}")" ;;
    esac

    pass="$(lsshm_server_config_effective_value passwordauthentication)"
    case "$pass" in
        no) lsshm_audit_pass "$(lsshm_t 'Password authentication disabled.')" ;;
        yes) lsshm_audit_warn "$(lsshm_t 'Password authentication enabled.')" ;;
        *) lsshm_audit_warn "$(lsshm_tf 'PasswordAuthentication = %s.' "${pass:-$(lsshm_t 'not set')}")" ;;
    esac

    maxauth="$(lsshm_server_config_effective_value maxauthtries)"
    if [ -n "$maxauth" ] && [ "$maxauth" -le 4 ] 2>/dev/null; then
        lsshm_audit_pass "$(lsshm_tf 'MaxAuthTries = %s.' "$maxauth")"
    else
        lsshm_audit_warn "$(lsshm_tf 'MaxAuthTries = %s (recommended <= 4).' "${maxauth:-$(lsshm_t 'default')}")"
    fi

    if lsshm_server_is_installed && lsshm_server_config_test >/dev/null 2>&1; then
        lsshm_audit_pass "$(lsshm_t 'sshd -t: configuration valid.')"
    elif lsshm_server_is_installed; then
        lsshm_audit_fail "$(lsshm_t 'sshd -t: configuration invalid.')"
    fi

    printf '\n%s%s%s\n' "${LSSHM_C_BOLD:-}" "$(lsshm_tf 'Local permissions (%s)' "$LSSHM_CALLING_USER")" "${LSSHM_C_RESET:-}"
    local ssh_dir; ssh_dir="$(lsshm_target_ssh_dir)"
    if [ -d "$ssh_dir" ]; then
        local perm; perm="$(stat -c '%a' "$ssh_dir" 2>/dev/null || stat -f '%Lp' "$ssh_dir" 2>/dev/null)"
        if [ "$perm" = "700" ]; then
            lsshm_audit_pass "$(lsshm_t 'The .ssh directory has 700 permissions.')"
        else
            lsshm_audit_warn "$(lsshm_tf 'The .ssh directory has %s permissions (expected 700).' "${perm:-$(lsshm_t 'unknown')}")"
        fi
        local ak="$ssh_dir/authorized_keys"
        if [ -f "$ak" ]; then
            perm="$(stat -c '%a' "$ak" 2>/dev/null || stat -f '%Lp' "$ak" 2>/dev/null)"
            [ "$perm" = "600" ] && lsshm_audit_pass "$(lsshm_t 'authorized_keys 600.')" \
                || lsshm_audit_warn "$(lsshm_tf 'authorized_keys %s (expected 600).' "${perm:-$(lsshm_t 'unknown')}")"
        fi
        local priv
        for priv in "$ssh_dir"/id_*; do
            [ -f "$priv" ] || continue
            case "$priv" in *.pub) continue ;; esac
            perm="$(stat -c '%a' "$priv" 2>/dev/null || stat -f '%Lp' "$priv" 2>/dev/null)"
            [ "$perm" = "600" ] && lsshm_audit_pass "$(lsshm_tf '%s 600.' "$(basename "$priv")")" \
                || lsshm_audit_fail "$(lsshm_tf '%s %s (private key must be 600).' "$(basename "$priv")" "${perm:-$(lsshm_t 'unknown')}")"
        done
    else
        lsshm_audit_warn "$(lsshm_tf 'No .ssh directory for %s.' "$LSSHM_CALLING_USER")"
    fi

    printf '\n%s%s%s\n' "${LSSHM_C_BOLD:-}" "$(lsshm_t 'Listening port')" "${LSSHM_C_RESET:-}"
    if lsshm_server_port_listening; then
        lsshm_audit_pass "$(lsshm_t 'The configured SSH port is listening.')"
    else
        lsshm_audit_warn "$(lsshm_t 'Unable to confirm the SSH port is listening.')"
    fi

    printf '\n%s%s%s : %s\n' \
        "${LSSHM_C_BOLD:-}" "$(lsshm_t 'Summary')" "${LSSHM_C_RESET:-}" \
        "$(lsshm_tf '%d OK, %d warnings, %d failures' "$LSSHM_AUDIT_PASS" "$LSSHM_AUDIT_WARN" "$LSSHM_AUDIT_FAIL")"

    [ "$LSSHM_AUDIT_FAIL" -eq 0 ]
}

# Doctor: environment and configuration diagnostics.
lsshm_doctor() {
    lsshm_header
    lsshm_out 'LSSHM diagnostics (doctor)'
    printf '\n'
    lsshm_platform_summary
    printf '\n'
    lsshm_info 'SSH tools:'
    local t
    for t in ssh sshd ssh-keygen ssh-add ssh-copy-id ssh-keyscan; do
        if lsshm_have "$t"; then printf '  [OK]  %s\n' "$t"; else printf '  [--]  %s (%s)\n' "$t" "$(lsshm_t 'absent')"; fi
    done
    printf '\n'
    lsshm_info 'LSSHM paths:'
    printf '  config : %s\n' "$LSSHM_CONFIG_DIR"
    printf '  data   : %s\n' "$LSSHM_DATA_DIR"
    printf '  state  : %s\n' "$LSSHM_STATE_DIR"
    printf '  cache  : %s\n' "$LSSHM_CACHE_DIR"
    printf '\n'
    lsshm_info 'PATH:'
    case ":$PATH:" in
        *":$LSSHM_BIN_DIR:"*) printf '  [OK]  %s\n' "$(lsshm_tf '%s is in PATH' "$LSSHM_BIN_DIR")" ;;
        *) printf '  [--]  %s\n' "$(lsshm_tf '%s is not in PATH' "$LSSHM_BIN_DIR")" ;;
    esac
}
