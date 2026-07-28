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
        lsshm_warn 'No server configuration to back up.'
        return 1
    fi
    if lsshm_run_privileged tar -czf "$archive" -T "$tmp" 2>/dev/null; then
        # When stdout is captured (rollback), emit only the path.
        # Interactively, show a human message instead.
        if [ -t 1 ]; then
            lsshm_ok 'Backup created: %s' "$archive"
        else
            printf '%s' "$archive"
        fi
        return 0
    fi
    lsshm_error 'Server configuration backup failed.'
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
        lsshm_info 'No backups recorded.'
        return 0
    fi
    lsshm_info 'Backups in %s:' "$LSSHM_BACKUP_DIR"
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
    [ -f "$archive" ] || lsshm_die 'Backup archive not found: %s' "$1"
    lsshm_warn 'Restoring server configuration from: %s' "$archive"
    lsshm_confirm "$(lsshm_t 'Confirm the restore?')" no || { lsshm_info 'Cancelled.'; return 1; }
    if lsshm_run_privileged tar -xzf "$archive" -C / ; then
        lsshm_ok 'Configuration restored.'
        lsshm_server_config_test && lsshm_server_reload
    else
        lsshm_error 'Restore failed.'
        return 1
    fi
}

lsshm_backup_menu() {
    while true; do
        local choice="" pick_ret=0
        if lsshm_uses_dialog_ui; then
            choice="$(lsshm_dialog_backup_menu)" || pick_ret=$?
            [ "$pick_ret" -ne 0 ] && break
        else
            clear 2>/dev/null || true
            lsshm_header
            lsshm_out 'Backup and restore'; printf '\n'
            lsshm_out '  1. Back up the SSH server configuration'
            lsshm_out '  2. Back up authorized keys (authorized_keys)'
            lsshm_out '  3. List backups'
            lsshm_out '  4. Restore a server configuration'
            lsshm_out '  5. Back'
            choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '5' || true)"
        fi
        case "$choice" in
            1) lsshm_ui_run "$(lsshm_t 'SSH server backup')" lsshm_backup_server_config ;;
            2) lsshm_ui_run "$(lsshm_t 'authorized_keys backup')" lsshm_backup_authorized_keys "$LSSHM_CALLING_USER" ;;
            3) lsshm_ui_run "$(lsshm_t 'Available backups')" lsshm_backup_list ;;
            4)
                if lsshm_uses_dialog_ui; then
                    lsshm_menu_try lsshm_ui_show "$(lsshm_t 'Backups')" lsshm_backup_list
                else
                    lsshm_menu_try lsshm_backup_list
                fi
                local a=""
                a="$(lsshm_prompt "$(lsshm_t 'Archive name to restore')" '' || true)"
                if [ -n "$a" ]; then
                    lsshm_menu_try lsshm_backup_restore_server "$a"
                fi
                lsshm_uses_dialog_ui || lsshm_pause
                ;;
            5|q|Q) break ;;
            *) lsshm_warn 'Invalid choice.'; lsshm_uses_dialog_ui || lsshm_pause ;;
        esac
    done
}
