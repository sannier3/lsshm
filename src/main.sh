# shellcheck shell=bash
# =============================================================================
# main.sh - entry point, argument parsing, command dispatch, install/uninstall
# =============================================================================

# Path to the running script (may be empty when piped from curl | bash).
lsshm_self_path() {
    local self="${BASH_SOURCE[0]:-$0}"
    if [ -f "$self" ]; then
        ( cd "$(dirname "$self")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$self")" )
    fi
}

lsshm_bootstrap() {
    lsshm_init_paths
    lsshm_init_colors
    lsshm_init_privileges
    lsshm_detect_platform
    lsshm_ensure_dirs
    lsshm_config_write_default
    lsshm_config_load
    trap lsshm_cleanup EXIT INT TERM
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
lsshm_usage() {
    cat <<EOF
$LSSHM_LONG_NAME v$LSSHM_VERSION

Usage :
  lsshm                     Ouvrir le menu CLI
  lsshm ui | --ui           Ouvrir l'interface dialog
  lsshm status              Afficher l'état SSH local
  lsshm doctor              Diagnostic de l'environnement
  lsshm audit               Audit de sécurité
  lsshm update [rollback]   Mettre à jour LSSHM (ou revenir en arrière)
  lsshm install             Installer LSSHM dans ~/.local
  lsshm uninstall           Désinstaller LSSHM
  lsshm version             Afficher la version
  lsshm help                Afficher cette aide

Options globales :
  --user NOM                Administrer les fichiers SSH de NOM (accès, clés, hosts)
  --ui                      Forcer l'interface dialog
  -y, --yes                 Répondre oui automatiquement (non interactif)
  --no-color                Désactiver la couleur
  -V, --version             Afficher la version
  -h, --help                Afficher cette aide

Serveur SSH local :
  lsshm server status|install|start|stop|restart|reload|enable|disable
  lsshm server config|test|logs

Accès entrants (clés autorisées ICI) :
  lsshm access list [--user U]
  lsshm access add [--user U]
  lsshm access remove [--user U]
  lsshm access disable [--user U]
  lsshm access repair [--user U]

Clés locales (pour se connecter AILLEURS) :
  lsshm key list|generate
  lsshm key inspect PATH
  lsshm key export PATH
  lsshm key delete PATH
  lsshm key agent list|add PATH|remove PATH

Machines distantes :
  lsshm host list|add
  lsshm host edit|delete|test|connect|copy-key|revoke-key NOM
EOF
}

# ---------------------------------------------------------------------------
# Installation / uninstallation
# ---------------------------------------------------------------------------
lsshm_path_in_file() {
    local file="$1"
    [ -f "$file" ] && grep -q '.local/bin' "$file" 2>/dev/null
}

lsshm_path_export_line() {
    printf '# Added by LSSHM\nexport PATH="$HOME/.local/bin:$PATH"\n'
}

lsshm_path_is_set() {
    case ":$PATH:" in
        *":$LSSHM_BIN_DIR:"*) return 0 ;;
    esac
    return 1
}

lsshm_path_activate_hint() {
    lsshm_info "Pour utiliser lsshm tout de suite (sans redémarrage ni reconnexion) :"
    printf '\n  export PATH="%s:$PATH"\n' "$LSSHM_BIN_DIR"
    printf '  lsshm\n\n'
    lsshm_info "Ou en une commande :"
    printf '  %s\n\n' "$LSSHM_BIN_LINK"
    lsshm_note "Les nouvelles sessions SSH chargeront ~/.profile automatiquement."
}

lsshm_check_path() {
    lsshm_path_is_set && return 0

    lsshm_warn "$LSSHM_BIN_DIR n'est pas dans votre PATH."
    if lsshm_confirm "Ajouter l'export PATH dans ~/.profile ?" yes; then
        local profile="$LSSHM_HOME/.profile"
        if ! lsshm_path_in_file "$profile"; then
            lsshm_path_export_line >>"$profile"
        fi
        # Shell interactif root (Debian, Proxmox) : ~/.bashrc est souvent lu à chaque session.
        local bashrc="$LSSHM_HOME/.bashrc"
        if [ -f "$bashrc" ] && ! lsshm_path_in_file "$bashrc"; then
            lsshm_path_export_line >>"$bashrc"
            lsshm_ok "Ajouté aussi à $bashrc (shell interactif)."
        fi
        lsshm_ok "PATH configuré dans $profile pour les prochaines connexions."
    else
        lsshm_info "Ajoutez manuellement : export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    lsshm_path_activate_hint
}

lsshm_install() {
    lsshm_header
    lsshm_info "Installation de LSSHM dans le répertoire utilisateur..."
    lsshm_ensure_dirs
    mkdir -p "$LSSHM_DATA_DIR" "$LSSHM_BIN_DIR"

    local self; self="$(lsshm_self_path)"
    if [ -n "$self" ] && [ -f "$self" ]; then
        install -m 0755 "$self" "$LSSHM_INSTALL_TARGET"
    else
        lsshm_info "Téléchargement de lsshm.sh depuis le dépôt..."
        local tmp; tmp="$(lsshm_mktemp)"
        lsshm_download "$LSSHM_REPO_RAW/lsshm.sh" "$tmp" || lsshm_die "Échec du téléchargement."
        bash -n "$tmp" || lsshm_die "Le script téléchargé est invalide."
        lsshm_update_verify_checksum "$tmp" || lsshm_die "Vérification SHA-256 échouée : installation annulée."
        install -m 0755 "$tmp" "$LSSHM_INSTALL_TARGET"
    fi

    ln -sf "$LSSHM_INSTALL_TARGET" "$LSSHM_BIN_LINK"
    lsshm_ok "Installé :"
    printf '  %s\n' "$LSSHM_INSTALL_TARGET"
    printf '  %s -> %s\n' "$LSSHM_BIN_LINK" "$LSSHM_INSTALL_TARGET"

    lsshm_config_write_default
    lsshm_check_path
    lsshm_ok "Installation terminée."
    if ! lsshm_path_is_set; then
        lsshm_note "La commande lsshm n'est pas encore active dans CE terminal."
        lsshm_path_activate_hint
    else
        lsshm_ok "Lancez : lsshm"
    fi
}

lsshm_uninstall() {
    lsshm_header
    lsshm_warn "Désinstallation de LSSHM."
    lsshm_confirm "Continuer ?" no || { lsshm_info "Annulé."; return 0; }

    rm -f "$LSSHM_BIN_LINK"
    rm -f "$LSSHM_INSTALL_TARGET" "$LSSHM_INSTALL_TARGET.prev"
    rmdir "$LSSHM_DATA_DIR" 2>/dev/null || true
    lsshm_ok "Binaire et lien supprimés."

    if lsshm_confirm "Supprimer aussi la configuration et l'état ($LSSHM_CONFIG_DIR, $LSSHM_STATE_DIR) ?" no; then
        rm -rf "$LSSHM_CONFIG_DIR" "$LSSHM_STATE_DIR" "$LSSHM_CACHE_DIR"
        lsshm_ok "Configuration et état supprimés."
    else
        lsshm_info "Configuration conservée : $LSSHM_CONFIG_DIR"
    fi
    lsshm_info "Note : LSSHM ne modifie pas votre configuration SSH lors de la désinstallation."
    lsshm_info "N'oubliez pas de retirer la ligne PATH de ~/.profile si nécessaire."
}

# ---------------------------------------------------------------------------
# Sub-command dispatchers
# ---------------------------------------------------------------------------
lsshm_cmd_server() {
    local sub="${1:-status}"; shift || true
    case "$sub" in
        status)  lsshm_server_status ;;
        install) lsshm_server_install ;;
        start)   lsshm_server_start ;;
        stop)    lsshm_server_stop ;;
        restart) lsshm_server_restart ;;
        reload)  lsshm_server_reload ;;
        enable)  lsshm_server_enable ;;
        disable) lsshm_server_disable ;;
        config)  lsshm_server_config_show ;;
        test)    lsshm_server_config_test && lsshm_ok "Configuration valide." ;;
        logs)    lsshm_server_logs "${1:-40}" ;;
        *) lsshm_error "Sous-commande server inconnue : $sub"; return 1 ;;
    esac
}

lsshm_cmd_access() {
    local sub="${1:-list}"; shift || true
    local user="$LSSHM_CALLING_USER" rest=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --user) user="${2:-}"; shift 2 || shift ;;
            --user=*) user="${1#*=}"; shift ;;
            *) rest+=("$1"); shift ;;
        esac
    done
    set -- "${rest[@]}"
    case "$sub" in
        list)    lsshm_access_list "$user" ;;
        add)     lsshm_access_add "$user" "${1:-}" ;;
        remove)  lsshm_access_remove "$user" "${1:-}" ;;
        disable) lsshm_access_disable "$user" "${1:-}" ;;
        repair)  lsshm_access_repair "$user" ;;
        *) lsshm_error "Sous-commande access inconnue : $sub"; return 1 ;;
    esac
}

lsshm_cmd_key() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)     lsshm_keys_list ;;
        generate) lsshm_keys_generate ;;
        inspect)  lsshm_keys_inspect "${1:-}" ;;
        export)   lsshm_keys_export "${1:-}" ;;
        delete)   lsshm_keys_delete "${1:-}" ;;
        agent)
            local asub="${1:-list}"; shift || true
            case "$asub" in
                list)   lsshm_agent_list ;;
                add)    lsshm_agent_add "${1:-}" ;;
                remove) lsshm_agent_remove "${1:-}" ;;
                *) lsshm_error "Sous-commande agent inconnue : $asub"; return 1 ;;
            esac
            ;;
        *) lsshm_error "Sous-commande key inconnue : $sub"; return 1 ;;
    esac
}

lsshm_cmd_host() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)      lsshm_hosts_list ;;
        add)       lsshm_hosts_add ;;
        edit)      lsshm_hosts_edit "${1:-}" ;;
        delete)    lsshm_hosts_delete "${1:-}" ;;
        test)      lsshm_hosts_test "${1:-}" ;;
        connect)   lsshm_hosts_connect "${1:-}" ;;
        copy-key)  lsshm_hosts_copy_key "${1:-}" ;;
        revoke-key) lsshm_hosts_revoke_key "${1:-}" ;;
        *) lsshm_error "Sous-commande host inconnue : $sub"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
lsshm_main() {
    # Parse global options; collect the remaining positional arguments.
    local args=() force_ui=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --user) LSSHM_TARGET_USER="${2:-}"; shift 2 || shift ;;
            --user=*) LSSHM_TARGET_USER="${1#*=}"; shift ;;
            --ui) force_ui=1; shift ;;
            -y|--yes) LSSHM_ASSUME_YES=1; shift ;;
            --no-color) LSSHM_NO_COLOR=1; shift ;;
            -V|--version) args+=("version"); shift ;;
            -h|--help) args+=("help"); shift ;;
            --) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done ;;
            *) args+=("$1"); shift ;;
        esac
    done

    lsshm_bootstrap
    # Re-init colors in case --no-color was set after init.
    lsshm_init_colors

    local cmd="${args[0]:-menu}"
    if [ "$force_ui" = "1" ]; then
        cmd="ui"
    fi

    # Target-user prompt is only for personal SSH file management — never for
    # install/uninstall/update/help/version (or server-only ops).
    case "$cmd" in
        install|uninstall|update|version|help|--help|-h|server) ;;
        *) lsshm_resolve_target_user ;;
    esac

    case "$cmd" in
        menu)
            lsshm_update_check || true
            lsshm_cli_main
            ;;
        ui) lsshm_dialog_main ;;
        status) lsshm_status_panel ;;
        doctor) lsshm_doctor ;;
        audit) lsshm_audit ;;
        update)
            case "${args[1]:-}" in
                rollback) lsshm_update_rollback ;;
                *) lsshm_update_run ;;
            esac
            ;;
        install) lsshm_install ;;
        uninstall) lsshm_uninstall ;;
        server) lsshm_cmd_server "${args[@]:1}" ;;
        access) lsshm_cmd_access "${args[@]:1}" ;;
        key)    lsshm_cmd_key "${args[@]:1}" ;;
        host)   lsshm_cmd_host "${args[@]:1}" ;;
        version) printf '%s v%s\n' "$LSSHM_NAME" "$LSSHM_VERSION" ;;
        help|--help|-h) lsshm_usage ;;
        *)
            lsshm_error "Commande inconnue : $cmd"
            lsshm_usage
            return 1
            ;;
    esac
}
