# shellcheck shell=bash
# =============================================================================
# dialog.sh - optional terminal user interface using `dialog`
# =============================================================================

lsshm_dialog_available() { lsshm_have dialog; }

# Offer to install dialog when missing.
lsshm_dialog_offer_install() {
    printf "L'interface graphique en terminal nécessite le paquet dialog.\n\n"
    printf '1. Installer dialog\n'
    printf '2. Continuer avec l’interface CLI\n'
    printf '3. Annuler\n\n'
    local choice; choice="$(lsshm_prompt 'Choix' '2')"
    case "$choice" in
        1)
            lsshm_dialog_install
            if lsshm_dialog_available; then
                return 0
            fi
            lsshm_warn "dialog n'a pas pu être installé. Passage à l'interface CLI."
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
        *)      lsshm_error "Gestionnaire de paquets non pris en charge : $LSSHM_PKG_MGR" ;;
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
    lsshm_dialog_menu_loop
}

lsshm_dialog_status_text() {
    lsshm_status_panel
}

lsshm_dialog_menu_loop() {
    while true; do
        local choice
        choice="$(dialog --clear --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
            --title "Menu principal" \
            --menu "$(lsshm_dialog_status_text)" 22 74 9 \
            1 "Gérer le serveur SSH local" \
            2 "Gérer les accès à cette machine" \
            3 "Gérer mes clés SSH" \
            4 "Gérer les machines distantes" \
            5 "Consulter les connexions et journaux" \
            6 "Effectuer un audit de sécurité" \
            7 "Sauvegarder ou restaurer" \
            8 "Paramètres de LSSHM" \
            9 "Quitter" \
            3>&1 1>&2 2>&3)" || break

        clear 2>/dev/null || true
        case "$choice" in
            1) lsshm_cli_server_menu ;;
            2) lsshm_cli_access_menu ;;
            3) lsshm_cli_keys_menu ;;
            4) lsshm_cli_hosts_menu ;;
            5) lsshm_logs_menu ;;
            6) lsshm_audit; lsshm_pause ;;
            7) lsshm_backup_menu ;;
            8) lsshm_settings_menu ;;
            9|"") break ;;
        esac
    done
    clear 2>/dev/null || true
}
