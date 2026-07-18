# shellcheck shell=bash
# =============================================================================
# ssh_agent.sh - manage keys loaded into ssh-agent
# =============================================================================

lsshm_agent_available() {
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
        lsshm_warn "Aucun ssh-agent détecté (SSH_AUTH_SOCK non défini)."
        lsshm_info "Démarrez un agent : eval \"\$(ssh-agent -s)\""
        return 1
    fi
    return 0
}

lsshm_agent_list() {
    lsshm_agent_available || return 1
    local tmp; tmp="$(lsshm_mktemp)"
    if ssh-add -l >"$tmp" 2>&1; then
        lsshm_info "Clés chargées dans ssh-agent :"
        cat "$tmp"
    else
        lsshm_info "$(cat "$tmp")"
    fi
}

lsshm_agent_add() {
    local path="${1:-}"
    lsshm_agent_available || return 1
    path="$(lsshm_keys_pick 'Clé à ajouter à ssh-agent' 1 "$path")" || return 1
    ssh-add "$path" && lsshm_ok "Clé ajoutée à ssh-agent."
}

lsshm_agent_remove() {
    local path="${1:-}"
    lsshm_agent_available || return 1
    if [ -z "$path" ]; then
        if lsshm_confirm "Retirer toutes les clés de l'agent ?" no; then
            ssh-add -D && lsshm_ok "Toutes les clés retirées."
            return 0
        fi
    fi
    path="$(lsshm_keys_pick 'Clé à retirer de ssh-agent' 1 "$path")" || return 1
    ssh-add -d "$path" && lsshm_ok "Clé retirée de ssh-agent."
}
