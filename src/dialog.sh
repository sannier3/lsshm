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
            --title "$title" --msgbox "(aucune sortie)" 8 50
        return 0
    fi
    dialog --clear --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
        --title "$title" --programbox "Résultat" 22 74 0 <"$tmp" \
        2>/dev/null || {
            local text; text="$(head -c 4000 "$tmp")"
            dialog --backtitle "$LSSHM_LONG_NAME v$LSSHM_VERSION" \
                --title "$title" --msgbox "$text" 22 74
        }
}

lsshm_ui_run() {
    local title="$1"; shift
    if lsshm_uses_dialog_ui; then
        lsshm_ui_show "$title" "$@"
    else
        "$@"
        lsshm_pause
    fi
}

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
    LSSHM_UI_MODE=1
    export LSSHM_UI_MODE
    lsshm_init_colors
    trap 'LSSHM_UI_MODE=0; lsshm_init_colors; lsshm_tty_restore' EXIT INT TERM
    lsshm_dialog_menu_loop
    LSSHM_UI_MODE=0
    lsshm_init_colors
    lsshm_tty_restore
}

lsshm_dialog_status_text() {
    lsshm_status_panel
}

lsshm_dialog_menu_loop() {
    while true; do
        local choice ret=0
        choice="$(lsshm_ui_menu "Menu principal" "$(lsshm_dialog_status_text)" \
            1 "Gérer le serveur SSH local" \
            2 "Gérer les accès à cette machine" \
            3 "Gérer mes clés SSH" \
            4 "Gérer les machines distantes" \
            5 "Consulter les connexions et journaux" \
            6 "Effectuer un audit de sécurité" \
            7 "Sauvegarder ou restaurer" \
            8 "Paramètres de LSSHM" \
            9 "Quitter")" || ret=$?

        [ "$ret" -ne 0 ] && break
        case "$choice" in
            1) lsshm_cli_server_menu ;;
            2) lsshm_cli_access_menu ;;
            3) lsshm_cli_keys_menu ;;
            4) lsshm_cli_hosts_menu ;;
            5) lsshm_logs_menu ;;
            6) lsshm_ui_run "Audit de sécurité" lsshm_audit ;;
            7) lsshm_backup_menu ;;
            8) lsshm_settings_menu ;;
            9) break ;;
        esac
    done
    lsshm_tty_restore
}

# --- dialog sub-menus (used when LSSHM_UI_MODE=1) ---------------------------

lsshm_dialog_server_menu() {
    local body
    body="$(lsshm_server_status 2>/dev/null)"
    lsshm_ui_menu "Serveur SSH local" "$body" \
        1 "Installer OpenSSH Server" \
        2 "Démarrer le service" \
        3 "Arrêter le service" \
        4 "Redémarrer le service" \
        5 "Recharger le service" \
        6 "Activer au démarrage" \
        7 "Désactiver au démarrage" \
        8 "Changer le port" \
        9 "Gérer l'accès root" \
        10 "Authentification par mot de passe" \
        11 "Authentification par clé" \
        12 "Utilisateurs autorisés (AllowUsers)" \
        13 "Groupes autorisés (AllowGroups)" \
        14 "Tester la configuration (sshd -t)" \
        15 "Afficher la configuration effective (sshd -T)" \
        16 "Voir les journaux" \
        17 "Retour"
}

lsshm_dialog_access_menu() {
    local user="$1" body
    body="Clés autorisées pour se connecter ICI
Utilisateur ciblé : $user"
    lsshm_ui_menu "Accès à cette machine" "$body" \
        1 "Lister les utilisateurs" \
        2 "Lister les clés autorisées" \
        3 "Ajouter une clé" \
        4 "Supprimer une clé" \
        5 "Désactiver / réactiver une clé" \
        6 "Réparer les permissions ~/.ssh" \
        7 "Détecter les doublons" \
        8 "Changer d'utilisateur ciblé" \
        9 "Retour"
}

lsshm_dialog_keys_menu() {
    lsshm_ui_menu "Mes clés SSH" "Clés utilisées pour se connecter AILLEURS" \
        1 "Lister les paires de clés" \
        2 "Générer une nouvelle clé (ED25519)" \
        3 "Inspecter une clé" \
        4 "Afficher / exporter une clé publique" \
        5 "Changer la phrase secrète" \
        6 "Supprimer une paire de clés" \
        7 "ssh-agent : lister" \
        8 "ssh-agent : ajouter une clé" \
        9 "ssh-agent : retirer une clé" \
        10 "Retour"
}

lsshm_dialog_hosts_menu() {
    lsshm_ui_menu "Machines distantes" "Gestion ~/.ssh/config (facultatif)" \
        1 "Lister les machines" \
        2 "Ajouter une machine" \
        3 "Modifier une machine" \
        4 "Supprimer une machine" \
        5 "Tester une machine" \
        6 "Configuration effective (ssh -G)" \
        7 "Se connecter à une machine" \
        8 "Copier une clé (ssh-copy-id)" \
        9 "Retirer une clé distante" \
        10 "known_hosts : lister" \
        11 "known_hosts : supprimer une empreinte" \
        12 "Retour"
}

lsshm_dialog_settings_menu() {
    lsshm_config_load
    local body
    body="Vérification des mises à jour : $LSSHM_CFG_UPDATE_CHECK
Canal : $LSSHM_CFG_UPDATE_CHANNEL
Fichier : $LSSHM_CONFIG_FILE"
    lsshm_ui_menu "Paramètres de LSSHM" "$body" \
        1 "Vérification : toujours" \
        2 "Vérification : une fois par jour" \
        3 "Vérification : jamais" \
        4 "Vérifier les mises à jour maintenant" \
        5 "Afficher le diagnostic (doctor)" \
        6 "Retour"
}

lsshm_dialog_logs_menu() {
    lsshm_ui_menu "Connexions et journaux" "Consulter l'activité SSH" \
        1 "Sessions actives" \
        2 "Connexions récentes" \
        3 "Tentatives échouées" \
        4 "Journaux du service SSH" \
        5 "Retour"
}

lsshm_dialog_backup_menu() {
    lsshm_ui_menu "Sauvegarde et restauration" "Sauvegarder ou restaurer la configuration SSH" \
        1 "Sauvegarder la configuration du serveur SSH" \
        2 "Sauvegarder les clés autorisées" \
        3 "Lister les sauvegardes" \
        4 "Restaurer une configuration serveur" \
        5 "Retour"
}
