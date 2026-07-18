# shellcheck shell=bash
# =============================================================================
# known_hosts.sh - manage ~/.ssh/known_hosts fingerprints
# =============================================================================

lsshm_known_hosts_file() {
    printf '%s/known_hosts' "$(lsshm_target_ssh_dir)"
}

lsshm_known_hosts_list() {
    local file; file="$(lsshm_known_hosts_file)"
    if [ ! -f "$file" ]; then
        lsshm_info "Aucun fichier known_hosts."
        return 0
    fi
    lsshm_info "Empreintes connues ($file) :"
    ssh-keygen -lf "$file" 2>/dev/null || awk '{print $1}' "$file"
}

lsshm_known_hosts_show() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt 'Nom ou adresse du serveur' '')"
    [ -n "$host" ] || return 1
    lsshm_info "Empreinte hôte pour $host :"
    ssh-keygen -F "$host" 2>/dev/null || lsshm_warn "Aucune entrée pour $host."
}

lsshm_known_hosts_remove() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt 'Hôte à supprimer de known_hosts' '')"
    [ -n "$host" ] || { lsshm_info "Annulé."; return 0; }
    local file; file="$(lsshm_known_hosts_file)"
    [ -f "$file" ] || { lsshm_error "Aucun fichier known_hosts."; return 1; }
    lsshm_backup_file "$file" "known-hosts" >/dev/null 2>&1 || true
    if ssh-keygen -R "$host" -f "$file" >/dev/null 2>&1; then
        lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
        [ -f "${file}.old" ] && lsshm_chown_user "$LSSHM_CALLING_USER" "${file}.old"
        lsshm_ok "Empreinte de $host supprimée."
    else
        lsshm_error "Échec de la suppression pour $host."
        return 1
    fi
}

lsshm_known_hosts_scan() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt 'Hôte à scanner' '')"
    [ -n "$host" ] || return 1
    lsshm_have ssh-keyscan || { lsshm_error "ssh-keyscan introuvable."; return 1; }
    lsshm_info "Empreinte annoncée par $host :"
    ssh-keyscan "$host" 2>/dev/null | ssh-keygen -lf - 2>/dev/null
}
