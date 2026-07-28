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
        lsshm_info 'No known_hosts file.'
        return 0
    fi
    lsshm_info 'Known fingerprints (%s):' "$file"
    ssh-keygen -lf "$file" 2>/dev/null || awk '{print $1}' "$file"
}

lsshm_known_hosts_show() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt "$(lsshm_t 'Server name or address')" '')"
    [ -n "$host" ] || return 1
    lsshm_info 'Host fingerprint for %s:' "$host"
    ssh-keygen -F "$host" 2>/dev/null || lsshm_warn 'No entry for %s.' "$host"
}

lsshm_known_hosts_remove() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt "$(lsshm_t 'Host to remove from known_hosts')" '')"
    [ -n "$host" ] || { lsshm_info 'Cancelled.'; return 0; }
    local file; file="$(lsshm_known_hosts_file)"
    [ -f "$file" ] || { lsshm_error 'No known_hosts file.'; return 1; }
    lsshm_backup_file "$file" "known-hosts" >/dev/null 2>&1 || true
    if ssh-keygen -R "$host" -f "$file" >/dev/null 2>&1; then
        lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
        [ -f "${file}.old" ] && lsshm_chown_user "$LSSHM_CALLING_USER" "${file}.old"
        lsshm_ok 'Fingerprint of %s removed.' "$host"
    else
        lsshm_error 'Removal failed for %s.' "$host"
        return 1
    fi
}

lsshm_known_hosts_scan() {
    local host="$1"
    [ -n "$host" ] || host="$(lsshm_prompt "$(lsshm_t 'Host to scan')" '')"
    [ -n "$host" ] || return 1
    lsshm_have ssh-keyscan || { lsshm_error 'ssh-keyscan not found.'; return 1; }
    lsshm_info 'Fingerprint announced by %s:' "$host"
    ssh-keyscan "$host" 2>/dev/null | ssh-keygen -lf - 2>/dev/null
}
