# shellcheck shell=bash
# =============================================================================
# ssh_agent.sh - manage keys loaded into ssh-agent
# =============================================================================

lsshm_agent_available() {
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
        lsshm_warn 'No ssh-agent detected (SSH_AUTH_SOCK not set).'
        lsshm_info 'Start an agent, e.g.: eval $(ssh-agent -s)'
        return 1
    fi
    return 0
}

lsshm_agent_list() {
    lsshm_agent_available || return 1
    local tmp; tmp="$(lsshm_mktemp)"
    if ssh-add -l >"$tmp" 2>&1; then
        lsshm_info 'Keys loaded in ssh-agent:'
        cat "$tmp"
    else
        lsshm_info "$(cat "$tmp")"
    fi
}

lsshm_agent_add() {
    local path="${1:-}"
    lsshm_agent_available || return 1
    path="$(lsshm_keys_pick 'Key to add to ssh-agent' 1 "$path")" || return 1
    ssh-add "$path" && lsshm_ok 'Key added to ssh-agent.'
}

lsshm_agent_remove() {
    local path="${1:-}"
    lsshm_agent_available || return 1
    if [ -z "$path" ]; then
        if lsshm_confirm "$(lsshm_t 'Remove all keys from the agent?')" no; then
            ssh-add -D && lsshm_ok 'All keys removed.'
            return 0
        fi
    fi
    path="$(lsshm_keys_pick 'Key to remove from ssh-agent' 1 "$path")" || return 1
    ssh-add -d "$path" && lsshm_ok 'Key removed from ssh-agent.'
}
