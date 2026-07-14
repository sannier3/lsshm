# shellcheck shell=bash
# =============================================================================
# users.sh - local user helpers
# =============================================================================

# List human/login users (UID >= 1000) plus root.
lsshm_users_list() {
    if lsshm_have getent; then
        getent passwd | awk -F: '($3==0)||($3>=1000 && $3<65534){print $1":"$3":"$6}'
    else
        awk -F: '($3==0)||($3>=1000 && $3<65534){print $1":"$3":"$6}' /etc/passwd
    fi
}

lsshm_users_print() {
    lsshm_info "Utilisateurs locaux :"
    local name uid home
    while IFS=: read -r name uid home; do
        printf '  %-16s uid=%-6s %s\n' "$name" "$uid" "$home"
    done <<EOF
$(lsshm_users_list)
EOF
}

lsshm_user_exists() {
    if lsshm_have getent; then
        getent passwd "$1" >/dev/null 2>&1
    else
        grep -q "^$1:" /etc/passwd 2>/dev/null
    fi
}

# Count authorized keys for a user. Quiet: returns 0 when unreadable without
# attempting privilege elevation (used in the status panel).
lsshm_user_key_count() {
    local user="$1" home ak count
    home="$(lsshm_user_home "$user")"
    ak="$home/.ssh/authorized_keys"
    if [ -r "$ak" ]; then
        count="$(grep -Ecv '^[[:space:]]*($|#)' "$ak" 2>/dev/null)"
        printf '%s' "${count:-0}"
    else
        printf '0'
    fi
}
