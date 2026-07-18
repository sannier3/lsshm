# shellcheck shell=bash
# =============================================================================
# logs.sh - sessions, logins, and SSH service logs
# =============================================================================

lsshm_logs_sessions() {
    lsshm_info "Sessions SSH actives :"
    if lsshm_have who; then
        who 2>/dev/null | grep -Ei 'pts|ssh' || who 2>/dev/null || lsshm_info "  (aucune)"
    else
        lsshm_warn "'who' indisponible."
    fi
}

lsshm_logs_recent_logins() {
    lsshm_info "Connexions récentes :"
    if lsshm_have last; then
        lsshm_run_privileged last -n 10 2>/dev/null | head -n 10 || true
    else
        lsshm_warn "'last' indisponible."
    fi
}

lsshm_logs_failed() {
    lsshm_info "Tentatives de connexion échouées récentes :"
    if lsshm_have lastb; then
        lsshm_run_privileged lastb -n 10 2>/dev/null | head -n 10 || lsshm_info "  (aucune ou non accessible)"
    elif [ -f /var/log/auth.log ]; then
        lsshm_run_privileged grep -i 'failed password' /var/log/auth.log 2>/dev/null | tail -n 10 || lsshm_info "  (aucune)"
    else
        lsshm_warn "Aucune source de tentatives échouées disponible."
    fi
}

lsshm_logs_service() {
    lsshm_info "Journaux du service SSH :"
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
            printf 'Connexions et journaux\n\n'
            cat <<EOF
  1. Sessions actives
  2. Connexions récentes
  3. Tentatives échouées
  4. Journaux du service SSH
  5. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '5' || true)"
        fi
        case "$choice" in
            1) lsshm_ui_run "Sessions actives" lsshm_logs_sessions ;;
            2) lsshm_ui_run "Connexions récentes" lsshm_logs_recent_logins ;;
            3) lsshm_ui_run "Tentatives échouées" lsshm_logs_failed ;;
            4) lsshm_ui_run "Journaux SSH" lsshm_logs_service ;;
            5|q|Q) break ;;
            *) lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}
