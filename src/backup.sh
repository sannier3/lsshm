# shellcheck shell=bash
# =============================================================================
# backup.sh - backup and restore of managed SSH files
# =============================================================================
# Backups are stored under $LSSHM_BACKUP_DIR as timestamped tar archives.

lsshm_backup_timestamp() { date '+%Y%m%d-%H%M%S'; }

# Copy a single file into a timestamped backup set, preserving path.
# Usage: lsshm_backup_file /etc/ssh/sshd_config [label]
lsshm_backup_file() {
    local src="$1" label="${2:-file}"
    [ -e "$src" ] || return 0
    lsshm_ensure_dirs
    local stamp; stamp="$(lsshm_backup_timestamp)"
    local dest="$LSSHM_BACKUP_DIR/${stamp}-${label}"
    mkdir -p "$dest" 2>/dev/null || true
    local base; base="$(basename "$src")"
    if [ -r "$src" ]; then
        cp -a "$src" "$dest/$base" 2>/dev/null || \
            lsshm_run_privileged cp -a "$src" "$dest/$base"
    else
        lsshm_run_privileged cp -a "$src" "$dest/$base"
    fi
    printf '%s' "$dest/$base"
    lsshm_log INFO "Backup of $src -> $dest/$base"
}

# Full backup of the SSH server configuration tree.
lsshm_backup_server_config() {
    lsshm_ensure_dirs
    local stamp; stamp="$(lsshm_backup_timestamp)"
    local archive="$LSSHM_BACKUP_DIR/${stamp}-sshd-config.tar.gz"
    local tmp; tmp="$(lsshm_mktemp)"
    {
        [ -f /etc/ssh/sshd_config ] && printf '/etc/ssh/sshd_config\n'
        [ -d /etc/ssh/sshd_config.d ] && printf '/etc/ssh/sshd_config.d\n'
    } >"$tmp"
    if [ ! -s "$tmp" ]; then
        lsshm_warn "Aucune configuration serveur à sauvegarder."
        return 1
    fi
    if lsshm_run_privileged tar -czf "$archive" -T "$tmp" 2>/dev/null; then
        lsshm_ok "Sauvegarde créée : $archive"
        printf '%s' "$archive"
        return 0
    fi
    lsshm_error "Échec de la sauvegarde de la configuration serveur."
    return 1
}

# Backup a user's authorized_keys.
lsshm_backup_authorized_keys() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local home; home="$(lsshm_user_home "$user")"
    lsshm_backup_file "$home/.ssh/authorized_keys" "authkeys-$user"
}

lsshm_backup_list() {
    lsshm_ensure_dirs
    if [ -z "$(ls -A "$LSSHM_BACKUP_DIR" 2>/dev/null)" ]; then
        lsshm_info "Aucune sauvegarde enregistrée."
        return 0
    fi
    lsshm_info "Sauvegardes dans $LSSHM_BACKUP_DIR :"
    local entry
    for entry in "$LSSHM_BACKUP_DIR"/*; do
        [ -e "$entry" ] || continue
        printf '  %s\n' "$(basename "$entry")"
    done
}

# Restore the SSH server configuration from an archive.
lsshm_backup_restore_server() {
    local archive="$1"
    if [ ! -f "$archive" ]; then
        # Allow passing just the basename.
        archive="$LSSHM_BACKUP_DIR/$archive"
    fi
    [ -f "$archive" ] || lsshm_die "Archive introuvable : $1"
    lsshm_warn "Restauration de la configuration serveur depuis : $archive"
    lsshm_confirm "Confirmer la restauration ?" no || { lsshm_info "Annulé."; return 1; }
    if lsshm_run_privileged tar -xzf "$archive" -C / ; then
        lsshm_ok "Configuration restaurée."
        lsshm_server_config_test && lsshm_server_reload
    else
        lsshm_error "Échec de la restauration."
        return 1
    fi
}

lsshm_backup_menu() {
    lsshm_header
    printf 'Sauvegarde et restauration\n\n'
    printf '  1. Sauvegarder la configuration du serveur SSH\n'
    printf '  2. Sauvegarder les clés autorisées (authorized_keys)\n'
    printf '  3. Lister les sauvegardes\n'
    printf '  4. Restaurer une configuration serveur\n'
    printf '  5. Retour\n\n'
    local choice; choice="$(lsshm_prompt 'Choix' '5')"
    case "$choice" in
        1) lsshm_backup_server_config ;;
        2) lsshm_backup_authorized_keys "$LSSHM_CALLING_USER" ;;
        3) lsshm_backup_list ;;
        4)
            lsshm_backup_list
            local a; a="$(lsshm_prompt 'Nom de l’archive à restaurer' '')"
            [ -n "$a" ] && lsshm_backup_restore_server "$a"
            ;;
        *) return 0 ;;
    esac
    lsshm_pause
}
