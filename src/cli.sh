# shellcheck shell=bash
# =============================================================================
# cli.sh - dependency-free CLI menus
# =============================================================================

# The status panel shown at the top of the main menu.
# Must not prompt for sudo: uses cached/non-interactive sshd -T or file parse.
lsshm_status_panel() {
    local active port root pass rootkeys userkeys hosts dump
    if lsshm_server_is_installed && lsshm_server_is_active; then active="actif"; else active="inactif"; fi

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

    cat <<EOF
Utilisateur administré : $LSSHM_CALLING_USER
État du serveur SSH : $active
Port : $port
Accès root : $root
Authentification par mot de passe : $pass
Clés autorisées pour root : $rootkeys
Clés privées de $LSSHM_CALLING_USER : $userkeys
Machines distantes enregistrées : $hosts
EOF
}

lsshm_cli_main() {
    lsshm_require_interactive
    while true; do
        clear 2>/dev/null || true
        lsshm_header
        lsshm_status_panel
        cat <<EOF

1. Gérer le serveur SSH local
2. Gérer les accès à cette machine
3. Gérer mes clés SSH
4. Gérer les machines distantes
5. Consulter les connexions et journaux
6. Effectuer un audit de sécurité
7. Sauvegarder ou restaurer
8. Paramètres de LSSHM
9. Quitter
EOF
        local choice; choice="$(lsshm_prompt 'Choix' '9')"
        case "$choice" in
            1) lsshm_cli_server_menu ;;
            2) lsshm_cli_access_menu ;;
            3) lsshm_cli_keys_menu ;;
            4) lsshm_cli_hosts_menu ;;
            5) lsshm_logs_menu ;;
            6) lsshm_audit; lsshm_pause ;;
            7) lsshm_backup_menu ;;
            8) lsshm_settings_menu ;;
            9|q|Q) break ;;
            *) lsshm_warn "Choix invalide." ; lsshm_pause ;;
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
            printf 'Serveur SSH local\n\n'
            lsshm_server_status
            cat <<EOF

 1. Installer OpenSSH Server
 2. Démarrer le service
 3. Arrêter le service
 4. Redémarrer le service
 5. Recharger le service
 6. Activer au démarrage
 7. Désactiver au démarrage
 8. Changer le port
 9. Gérer l'accès root
10. Authentification par mot de passe
11. Authentification par clé
12. Utilisateurs autorisés (AllowUsers)
13. Groupes autorisés (AllowGroups)
14. Tester la configuration (sshd -t)
15. Afficher la configuration effective (sshd -T)
16. Voir les journaux
17. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '17')"
        fi
        case "$choice" in
            1)  lsshm_ui_run "Installation OpenSSH Server" lsshm_server_install ;;
            2)  lsshm_ui_run "Démarrage SSH" lsshm_server_start ;;
            3)  lsshm_ui_run "Arrêt SSH" lsshm_server_stop ;;
            4)  lsshm_ui_run "Redémarrage SSH" lsshm_server_restart ;;
            5)  lsshm_ui_run "Rechargement SSH" lsshm_server_reload ;;
            6)  lsshm_ui_run "Activation au démarrage" lsshm_server_enable ;;
            7)  lsshm_ui_run "Désactivation au démarrage" lsshm_server_disable ;;
            8)  lsshm_set_port; lsshm_uses_dialog_ui || lsshm_pause ;;
            9)  lsshm_set_root_login; lsshm_uses_dialog_ui || lsshm_pause ;;
            10) lsshm_set_password_auth; lsshm_uses_dialog_ui || lsshm_pause ;;
            11) lsshm_set_pubkey_auth; lsshm_uses_dialog_ui || lsshm_pause ;;
            12) lsshm_set_allow_users; lsshm_uses_dialog_ui || lsshm_pause ;;
            13) lsshm_set_allow_groups; lsshm_uses_dialog_ui || lsshm_pause ;;
            14) lsshm_ui_run "Test sshd -t" lsshm_server_config_test ;;
            15)
                if lsshm_uses_dialog_ui; then
                    lsshm_ui_show "Configuration effective" lsshm_server_config_show
                else
                    lsshm_server_config_show | ${PAGER:-less} 2>/dev/null || lsshm_server_config_show
                    lsshm_pause
                fi
                ;;
            16) lsshm_ui_run "Journaux SSH" lsshm_server_logs ;;
            17|q|Q) break ;;
            *)  lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
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
            printf 'Accès à cette machine (clés autorisées pour se connecter ICI)\n'
            printf 'Utilisateur ciblé : %s\n\n' "$user"
            cat <<EOF
1. Lister les utilisateurs
2. Lister les clés autorisées
3. Ajouter une clé (coller ou importer un .pub)
4. Supprimer une clé
5. Désactiver / réactiver une clé
6. Réparer les permissions ~/.ssh
7. Détecter les doublons
8. Changer d'utilisateur ciblé
9. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '9')"
        fi
        case "$choice" in
            1) lsshm_ui_run "Utilisateurs locaux" lsshm_users_print ;;
            2) lsshm_ui_run "Clés autorisées" lsshm_access_list "$user" ;;
            3) lsshm_access_add "$user"; lsshm_uses_dialog_ui || lsshm_pause ;;
            4) lsshm_access_remove "$user"; lsshm_uses_dialog_ui || lsshm_pause ;;
            5) lsshm_access_disable "$user"; lsshm_uses_dialog_ui || lsshm_pause ;;
            6) lsshm_ui_run "Réparation permissions" lsshm_access_repair "$user" ;;
            7) lsshm_ui_run "Doublons" lsshm_access_duplicates "$user" ;;
            8) lsshm_pick_target_user "$user"; lsshm_uses_dialog_ui || lsshm_pause ;;
            9|q|Q) break ;;
            *) lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
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
            printf 'Clés SSH de %s (pour se connecter AILLEURS)\n' "$LSSHM_CALLING_USER"
            printf 'Répertoire : %s\n\n' "$(lsshm_keys_dir)"
            cat <<EOF
1. Lister les paires de clés
2. Générer une nouvelle clé (ED25519 par défaut)
3. Inspecter une clé
4. Afficher / exporter une clé publique
5. Changer la phrase secrète
6. Supprimer une paire de clés
7. ssh-agent : lister
8. ssh-agent : ajouter une clé
9. ssh-agent : retirer une clé
10. Changer d'utilisateur ciblé
11. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '11')"
        fi
        case "$choice" in
            1)  lsshm_ui_run "Paires de clés" lsshm_keys_list ;;
            2)  lsshm_keys_generate; lsshm_uses_dialog_ui || lsshm_pause ;;
            3)  lsshm_keys_inspect ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            4)  lsshm_ui_run "Clé publique" lsshm_keys_export "" ;;
            5)  lsshm_keys_passphrase ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            6)  lsshm_keys_delete ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            7)  lsshm_ui_run "ssh-agent" lsshm_agent_list ;;
            8)  lsshm_agent_add ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            9)  lsshm_agent_remove ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            10) lsshm_pick_target_user "$LSSHM_CALLING_USER"; lsshm_uses_dialog_ui || lsshm_pause ;;
            11|q|Q) break ;;
            *)  lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
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
            printf 'Machines distantes (~/.ssh/config) - facultatif\n'
            printf 'Utilisateur : %s\n\n' "$LSSHM_CALLING_USER"
            cat <<EOF
 1. Lister les machines
 2. Ajouter une machine
 3. Modifier une machine
 4. Supprimer une machine
 5. Tester une machine (résolution, port, auth)
 6. Configuration effective (ssh -G)
 7. Se connecter à une machine
 8. Copier une clé (ssh-copy-id)
 9. Retirer une clé distante
10. known_hosts : lister
11. known_hosts : supprimer une empreinte
12. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '12')"
        fi
        case "$choice" in
            1)  lsshm_ui_run "Machines distantes" lsshm_hosts_list ;;
            2)  lsshm_hosts_add; lsshm_uses_dialog_ui || lsshm_pause ;;
            3)  lsshm_hosts_edit ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            4)  lsshm_hosts_delete ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            5)  lsshm_ui_run "Test machine" lsshm_hosts_test "" ;;
            6)  lsshm_ui_run "Configuration effective" lsshm_hosts_effective "" ;;
            7)  lsshm_hosts_connect "" ;;
            8)  lsshm_hosts_copy_key ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            9)  lsshm_hosts_revoke_key ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            10) lsshm_ui_run "known_hosts" lsshm_known_hosts_list ;;
            11) lsshm_known_hosts_remove ""; lsshm_uses_dialog_ui || lsshm_pause ;;
            12|q|Q) break ;;
            *)  lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
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
            printf 'Paramètres de LSSHM\n\n'
            printf 'Utilisateur administré        : %s\n' "$LSSHM_CALLING_USER"
            printf 'Vérification des mises à jour : %s\n' "$LSSHM_CFG_UPDATE_CHECK"
            printf 'Canal de mise à jour          : %s\n' "$LSSHM_CFG_UPDATE_CHANNEL"
            printf 'Fichier de configuration      : %s\n\n' "$LSSHM_CONFIG_FILE"
            cat <<EOF
1. Vérification : toujours
2. Vérification : une fois par jour
3. Vérification : jamais
4. Vérifier les mises à jour maintenant
5. Afficher le diagnostic (doctor)
6. Changer d'utilisateur administré
7. Retour
EOF
            choice="$(lsshm_prompt 'Choix' '7')"
        fi
        case "$choice" in
            1) lsshm_config_set update_check always; lsshm_config_load ;;
            2) lsshm_config_set update_check daily; lsshm_config_load ;;
            3) lsshm_config_set update_check never; lsshm_config_load ;;
            4) LSSHM_CFG_UPDATE_CHECK=always lsshm_update_run; lsshm_uses_dialog_ui || lsshm_pause ;;
            5) lsshm_ui_run "Diagnostic LSSHM" lsshm_doctor ;;
            6) lsshm_pick_target_user "$LSSHM_CALLING_USER"; lsshm_uses_dialog_ui || lsshm_pause ;;
            7|q|Q) break ;;
            *) lsshm_warn "Choix invalide."; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}
