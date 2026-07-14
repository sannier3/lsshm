# shellcheck shell=bash
# =============================================================================
# rollback.sh - safe application of dangerous changes with automatic rollback
# =============================================================================
# Dangerous changes (port, disabling passwords, root access, AllowUsers,
# ListenAddress) can lock a remote administrator out. LSSHM therefore:
#   1. backs up the configuration
#   2. schedules an automatic restore
#   3. applies the change and reloads SSH
#   4. verifies the port is listening
#   5. asks for confirmation from a second session
#   6. cancels the automatic restore only after confirmation

LSSHM_ROLLBACK_UNIT="lsshm-rollback"
LSSHM_ROLLBACK_DELAY="${LSSHM_ROLLBACK_DELAY:-120}"

# Build a self-contained restore script that reverts to a backup archive.
lsshm_rollback_build_script() {
    local archive="$1" confirm_flag="$2" delay="$3"
    local script; script="$(lsshm_mktemp)"
    cat >"$script" <<EOF
#!/bin/sh
# LSSHM automatic rollback helper
sleep "$delay"
if [ -f "$confirm_flag" ]; then
    rm -f "$confirm_flag"
    exit 0
fi
tar -xzf "$archive" -C / 2>/dev/null
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload "$LSSHM_SSH_SERVICE" 2>/dev/null || systemctl restart "$LSSHM_SSH_SERVICE" 2>/dev/null
elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$LSSHM_SSH_SERVICE" restart 2>/dev/null
else
    service "$LSSHM_SSH_SERVICE" restart 2>/dev/null
fi
EOF
    chmod +x "$script"
    printf '%s' "$script"
}

lsshm_rollback_schedule() {
    # lsshm_rollback_schedule SCRIPT DELAY -> echoes cancel token
    local script="$1" delay="$2"
    if [ "$LSSHM_HAS_SYSTEMD" = "1" ] && lsshm_have systemd-run; then
        lsshm_run_privileged systemd-run --unit="$LSSHM_ROLLBACK_UNIT" \
            --description="LSSHM automatic SSH rollback" \
            /bin/sh "$script" >/dev/null 2>&1 && { printf 'systemd'; return 0; }
    fi
    # Fallback: detached nohup process. Cancellation relies on the confirm flag.
    lsshm_run_privileged sh -c "nohup /bin/sh '$script' >/dev/null 2>&1 &"
    printf 'nohup'
}

lsshm_rollback_cancel() {
    local method="$1" confirm_flag="$2"
    # The confirm flag stops both methods when the helper wakes up.
    lsshm_run_privileged touch "$confirm_flag" 2>/dev/null || true
    if [ "$method" = "systemd" ] && lsshm_have systemctl; then
        lsshm_run_privileged systemctl stop "$LSSHM_ROLLBACK_UNIT" 2>/dev/null || true
        lsshm_run_privileged systemctl reset-failed "$LSSHM_ROLLBACK_UNIT" 2>/dev/null || true
    fi
}

# Main entry used by server_config.sh for dangerous directives.
lsshm_apply_dangerous_change() {
    local key="$1" value="$2" description="$3"

    lsshm_warn "Changement sensible : $description"
    if ! lsshm_confirm "Continuer avec une restauration automatique de sécurité ?" no; then
        lsshm_info "Annulé."
        return 1
    fi

    # 1. Backup.
    local archive; archive="$(lsshm_backup_server_config)" || return 1

    # 2. Apply the change (validates internally).
    if ! lsshm_managed_set "$key" "$value"; then
        lsshm_error "Application annulée."
        return 1
    fi

    # Non-interactive: apply and reload without arming a rollback prompt.
    if ! lsshm_is_interactive; then
        lsshm_server_reload
        return 0
    fi

    # 3. Schedule automatic restore.
    local confirm_flag="$LSSHM_STATE_DIR/rollback.confirm"
    lsshm_run_privileged rm -f "$confirm_flag" 2>/dev/null || true
    local script; script="$(lsshm_rollback_build_script "$archive" "$confirm_flag" "$LSSHM_ROLLBACK_DELAY")"
    local method; method="$(lsshm_rollback_schedule "$script" "$LSSHM_ROLLBACK_DELAY")"

    # 4. Reload SSH.
    lsshm_server_reload || true

    # 5. Verify the port listens.
    if lsshm_server_port_listening; then
        lsshm_ok "Le port SSH écoute."
    else
        lsshm_warn "Impossible de confirmer que le port SSH écoute."
    fi

    # 6. Ask for confirmation from a second session.
    cat <<EOF

La nouvelle configuration est active.

Une restauration automatique aura lieu dans ${LSSHM_ROLLBACK_DELAY} secondes.

Ouvrez une seconde connexion SSH avant de confirmer.

  1. La nouvelle connexion fonctionne
  2. Restaurer immédiatement
EOF
    local choice; choice="$(lsshm_prompt 'Choix' '2')"
    case "$choice" in
        1)
            lsshm_rollback_cancel "$method" "$confirm_flag"
            lsshm_ok "Restauration automatique annulée. Changement conservé."
            ;;
        *)
            lsshm_warn "Restauration immédiate..."
            lsshm_run_privileged tar -xzf "$archive" -C / 2>/dev/null || true
            lsshm_rollback_cancel "$method" "$confirm_flag"
            lsshm_server_reload || true
            lsshm_ok "Configuration précédente restaurée."
            ;;
    esac
}
