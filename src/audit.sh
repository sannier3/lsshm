# shellcheck shell=bash
# =============================================================================
# audit.sh - local SSH security audit and diagnostics
# =============================================================================

LSSHM_AUDIT_PASS=0
LSSHM_AUDIT_WARN=0
LSSHM_AUDIT_FAIL=0

lsshm_audit_pass() { LSSHM_AUDIT_PASS=$((LSSHM_AUDIT_PASS+1)); printf '  [%sOK%s]   %s\n' "${LSSHM_C_GREEN:-}" "${LSSHM_C_RESET:-}" "$*"; }
lsshm_audit_warn() { LSSHM_AUDIT_WARN=$((LSSHM_AUDIT_WARN+1)); printf '  [%sAVERT%s] %s\n' "${LSSHM_C_YELLOW:-}" "${LSSHM_C_RESET:-}" "$*"; }
lsshm_audit_fail() { LSSHM_AUDIT_FAIL=$((LSSHM_AUDIT_FAIL+1)); printf '  [%sÉCHEC%s] %s\n' "${LSSHM_C_RED:-}" "${LSSHM_C_RESET:-}" "$*"; }

lsshm_audit() {
    LSSHM_AUDIT_PASS=0; LSSHM_AUDIT_WARN=0; LSSHM_AUDIT_FAIL=0
    lsshm_header
    printf 'Audit de sécurité SSH local\n\n'

    printf '%sServeur SSH%s\n' "${LSSHM_C_BOLD:-}" "${LSSHM_C_RESET:-}"
    if lsshm_server_is_installed; then
        lsshm_audit_pass "OpenSSH Server installé."
    else
        lsshm_audit_warn "OpenSSH Server non installé."
    fi

    local root pass maxauth
    root="$(lsshm_server_config_effective_value permitrootlogin)"
    case "$root" in
        no) lsshm_audit_pass "PermitRootLogin = no (root interdit)." ;;
        prohibit-password|without-password) lsshm_audit_pass "PermitRootLogin = clé uniquement." ;;
        yes) lsshm_audit_fail "PermitRootLogin = yes (root avec mot de passe autorisé)." ;;
        *) lsshm_audit_warn "PermitRootLogin = ${root:-non défini}." ;;
    esac

    pass="$(lsshm_server_config_effective_value passwordauthentication)"
    case "$pass" in
        no) lsshm_audit_pass "Authentification par mot de passe désactivée." ;;
        yes) lsshm_audit_warn "Authentification par mot de passe activée." ;;
        *) lsshm_audit_warn "PasswordAuthentication = ${pass:-non défini}." ;;
    esac

    maxauth="$(lsshm_server_config_effective_value maxauthtries)"
    if [ -n "$maxauth" ] && [ "$maxauth" -le 4 ] 2>/dev/null; then
        lsshm_audit_pass "MaxAuthTries = $maxauth."
    else
        lsshm_audit_warn "MaxAuthTries = ${maxauth:-défaut} (recommandé <= 4)."
    fi

    if lsshm_server_is_installed && lsshm_server_config_test >/dev/null 2>&1; then
        lsshm_audit_pass "sshd -t : configuration valide."
    elif lsshm_server_is_installed; then
        lsshm_audit_fail "sshd -t : configuration invalide."
    fi

    printf '\n%sPermissions locales (%s)%s\n' "${LSSHM_C_BOLD:-}" "$LSSHM_CALLING_USER" "${LSSHM_C_RESET:-}"
    local ssh_dir; ssh_dir="$(lsshm_target_ssh_dir)"
    if [ -d "$ssh_dir" ]; then
        local perm; perm="$(stat -c '%a' "$ssh_dir" 2>/dev/null || stat -f '%Lp' "$ssh_dir" 2>/dev/null)"
        if [ "$perm" = "700" ]; then
            lsshm_audit_pass "Le dossier .ssh a les permissions 700."
        else
            lsshm_audit_warn "Le dossier .ssh a les permissions ${perm:-inconnues} (attendu 700)."
        fi
        local ak="$ssh_dir/authorized_keys"
        if [ -f "$ak" ]; then
            perm="$(stat -c '%a' "$ak" 2>/dev/null || stat -f '%Lp' "$ak" 2>/dev/null)"
            [ "$perm" = "600" ] && lsshm_audit_pass "authorized_keys 600." \
                || lsshm_audit_warn "authorized_keys ${perm:-inconnu} (attendu 600)."
        fi
        local priv
        for priv in "$ssh_dir"/id_*; do
            [ -f "$priv" ] || continue
            case "$priv" in *.pub) continue ;; esac
            perm="$(stat -c '%a' "$priv" 2>/dev/null || stat -f '%Lp' "$priv" 2>/dev/null)"
            [ "$perm" = "600" ] && lsshm_audit_pass "$(basename "$priv") 600." \
                || lsshm_audit_fail "$(basename "$priv") ${perm:-inconnu} (clé privée doit être 600)."
        done
    else
        lsshm_audit_warn "Aucun répertoire .ssh pour $LSSHM_CALLING_USER."
    fi

    printf '\n%sPort d’écoute%s\n' "${LSSHM_C_BOLD:-}" "${LSSHM_C_RESET:-}"
    if lsshm_server_port_listening; then
        lsshm_audit_pass "Le port SSH configuré écoute."
    else
        lsshm_audit_warn "Impossible de confirmer l'écoute du port SSH."
    fi

    printf '\n%sRésumé%s : %d OK, %d avertissements, %d échecs\n' \
        "${LSSHM_C_BOLD:-}" "${LSSHM_C_RESET:-}" \
        "$LSSHM_AUDIT_PASS" "$LSSHM_AUDIT_WARN" "$LSSHM_AUDIT_FAIL"

    [ "$LSSHM_AUDIT_FAIL" -eq 0 ]
}

# Doctor: environment and configuration diagnostics.
lsshm_doctor() {
    lsshm_header
    printf 'Diagnostic LSSHM (doctor)\n\n'
    lsshm_platform_summary
    printf '\n'
    lsshm_info "Outils SSH :"
    local t
    for t in ssh sshd ssh-keygen ssh-add ssh-copy-id ssh-keyscan; do
        if lsshm_have "$t"; then printf '  [OK]  %s\n' "$t"; else printf '  [--]  %s (absent)\n' "$t"; fi
    done
    printf '\n'
    lsshm_info "Chemins LSSHM :"
    printf '  config : %s\n' "$LSSHM_CONFIG_DIR"
    printf '  data   : %s\n' "$LSSHM_DATA_DIR"
    printf '  state  : %s\n' "$LSSHM_STATE_DIR"
    printf '  cache  : %s\n' "$LSSHM_CACHE_DIR"
    printf '\n'
    lsshm_info "PATH :"
    case ":$PATH:" in
        *":$LSSHM_BIN_DIR:"*) printf '  [OK]  %s est dans le PATH\n' "$LSSHM_BIN_DIR" ;;
        *) printf '  [--]  %s absent du PATH\n' "$LSSHM_BIN_DIR" ;;
    esac
}
