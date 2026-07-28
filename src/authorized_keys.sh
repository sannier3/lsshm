# shellcheck shell=bash
# =============================================================================
# authorized_keys.sh - incoming access: keys allowed to reach THIS machine
# =============================================================================
# This manages ~/.ssh/authorized_keys for a given user. These are the public
# keys that are ALLOWED TO CONNECT to this machine.

lsshm_access_file() {
    local user="${1:-$LSSHM_CALLING_USER}"
    printf '%s/.ssh/authorized_keys' "$(lsshm_user_home "$user")"
}

# Read the authorized_keys file (with privileges if needed).
lsshm_access_read() {
    local file="$1"
    if [ -r "$file" ]; then
        cat "$file"
    elif lsshm_can_elevate; then
        lsshm_run_privileged cat "$file" 2>/dev/null
    fi
}

# Compute the SHA256 fingerprint and type of a single key line.
lsshm_access_fingerprint_line() {
    local line="$1" tmp out
    tmp="$(lsshm_mktemp)"
    printf '%s\n' "$line" >"$tmp"
    out="$(ssh-keygen -lf "$tmp" 2>/dev/null)" || { printf ''; return 1; }
    printf '%s' "$out"
}

# Classify a line from authorized_keys for shared indexing.
# Sets: _ak_kind (active|disabled|skip), _ak_keyline (raw key line to fingerprint).
lsshm_access_classify_line() {
    local line="$1"
    _ak_kind="skip"
    _ak_keyline=""
    case "$line" in
        '# LSSHM-DISABLED '*)
            _ak_kind="disabled"
            _ak_keyline="${line#\# LSSHM-DISABLED }"
            ;;
        ''|'#'*)
            _ak_kind="skip"
            ;;
        *)
            _ak_kind="active"
            _ak_keyline="$line"
            ;;
    esac
}

# List authorized keys for a user with details.
# Indexing includes both active and LSSHM-DISABLED entries (same as remove/disable).
lsshm_access_list() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local file; file="$(lsshm_access_file "$user")"
    lsshm_out 'User : %s' "$user"
    lsshm_out 'File : %s' "$file"
    printf '\n'

    local content; content="$(lsshm_access_read "$file")"
    if [ -z "$content" ]; then
        lsshm_info 'No authorized key.'
        return 0
    fi

    local i=0 line fp bits type comment info
    while IFS= read -r line; do
        lsshm_access_classify_line "$line"
        [ "$_ak_kind" = "skip" ] && continue
        i=$((i+1))
        info="$(lsshm_access_fingerprint_line "$_ak_keyline")"
        bits="$(printf '%s' "$info" | awk '{print $1}')"
        fp="$(printf '%s' "$info" | awk '{print $2}')"
        type="$(printf '%s' "$info" | awk '{print $NF}' | tr -d '()')"
        # Comment = fields after key type + key body (options may precede the type).
        comment="$(printf '%s' "$_ak_keyline" | awk '
            {
              for (i=1;i<=NF;i++) {
                if ($i ~ /^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)$/) {
                  if (i+2<=NF) { for (j=i+2;j<=NF;j++) printf "%s%s", $j, (j<NF?" ":""); }
                  exit
                }
              }
            }')"
        local nocomment; nocomment="$(lsshm_t 'no comment')"
        if [ "$_ak_kind" = "disabled" ]; then
            printf '%d. [%s] %s\n' "$i" "$(lsshm_t 'DISABLED')" "${comment:-$nocomment}"
        else
            printf '%d. %s\n' "$i" "${comment:-$nocomment}"
        fi
        lsshm_out '   Type        : %s (%s bits)' "${type:-?}" "${bits:-?}"
        lsshm_out '   Fingerprint : %s' "${fp:-$(lsshm_t 'unknown')}"
        case "$_ak_keyline" in
            *from=*)       lsshm_out '   Restriction : %s' "$(printf '%s' "$_ak_keyline" | grep -o 'from="[^"]*"')" ;;
        esac
        case "$_ak_keyline" in
            *command=*)    lsshm_out '   Command     : %s' "$(printf '%s' "$_ak_keyline" | grep -o 'command="[^"]*"')" ;;
        esac
        case "$_ak_keyline" in
            *no-port-forwarding*) lsshm_out '   Forwarding  : forbidden' ;;
        esac
    done <<EOF
$content
EOF
}

# Write new content to the authorized_keys file with correct ownership/perms.
lsshm_access_write() {
    local user="$1" file="$2" tmp="$3"
    local home; home="$(lsshm_user_home "$user")"
    local ssh_dir="$home/.ssh"
    local uid gid
    uid="$(id -u "$user" 2>/dev/null || echo 0)"
    gid="$(id -g "$user" 2>/dev/null || echo 0)"

    # As root, always set ownership: writable dirs would otherwise leave
    # root:root files that StrictModes rejects for the target user.
    if [ "${LSSHM_IS_ROOT:-0}" = "1" ]; then
        mkdir -p "$ssh_dir"
        install -m 0600 -o "$uid" -g "$gid" "$tmp" "$file"
        chmod 700 "$ssh_dir"
        chown "$uid:$gid" "$ssh_dir"
    elif [ -w "$ssh_dir" ] || { [ ! -e "$ssh_dir" ] && [ -w "$home" ]; }; then
        mkdir -p "$ssh_dir"
        install -m 0600 "$tmp" "$file"
        chmod 700 "$ssh_dir"
    else
        lsshm_run_privileged mkdir -p "$ssh_dir"
        lsshm_run_privileged install -m 0600 -o "$uid" -g "$gid" "$tmp" "$file"
        lsshm_run_privileged chmod 700 "$ssh_dir"
        lsshm_run_privileged chown "$uid:$gid" "$ssh_dir"
    fi
}

# Add a public key (pasted or from a .pub file).
lsshm_access_add() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local keyline="${2:-}"
    if [ -z "$keyline" ]; then
        if lsshm_is_interactive; then
            lsshm_out 'Paste the public key (one line), then Enter:'
            read -r keyline </dev/tty || keyline=""
        fi
    fi
    # Support importing from a file path.
    if [ -f "$keyline" ]; then
        keyline="$(cat "$keyline")"
    fi
    [ -n "$keyline" ] || { lsshm_error 'No key provided.'; return 1; }

    # Validate that it parses as a key.
    if ! lsshm_access_fingerprint_line "$keyline" >/dev/null; then
        lsshm_error 'The provided key is not a valid public key.'
        return 1
    fi

    local file; file="$(lsshm_access_file "$user")"
    lsshm_backup_authorized_keys "$user" >/dev/null 2>&1 || true
    local tmp; tmp="$(lsshm_mktemp)"
    lsshm_access_read "$file" >"$tmp" 2>/dev/null || true

    # Duplicate detection by fingerprint (active and LSSHM-DISABLED entries).
    local newfp; newfp="$(lsshm_access_fingerprint_line "$keyline" | awk '{print $2}')"
    local existing efp
    while IFS= read -r existing || [ -n "$existing" ]; do
        lsshm_access_classify_line "$existing"
        [ "$_ak_kind" = "skip" ] && continue
        efp="$(lsshm_access_fingerprint_line "$_ak_keyline" | awk '{print $2}')"
        if [ -n "$efp" ] && [ "$efp" = "$newfp" ]; then
            if [ "$_ak_kind" = "disabled" ]; then
                lsshm_warn 'This key already exists (disabled, fingerprint %s).' "$efp"
                lsshm_info 'Re-enable it via the Disable / re-enable a key entry.'
            else
                lsshm_warn 'This key is already authorized (fingerprint %s).' "$efp"
            fi
            return 0
        fi
    done <"$tmp"

    printf '%s\n' "$keyline" >>"$tmp"
    lsshm_access_write "$user" "$file" "$tmp"
    lsshm_ok 'Key added for %s.' "$user"
}

# Remove a key by fingerprint or by 1-based index (same numbering as list).
lsshm_access_remove() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local target="${2:-}"
    local file; file="$(lsshm_access_file "$user")"
    local content; content="$(lsshm_access_read "$file")"
    [ -n "$content" ] || { lsshm_info 'No key to remove.'; return 0; }

    if [ -z "$target" ]; then
        lsshm_access_list "$user"
        target="$(lsshm_prompt "$(lsshm_t 'SHA256 fingerprint or number to remove')" '')"
    fi
    [ -n "$target" ] || { lsshm_info 'Cancelled.'; return 0; }

    lsshm_backup_authorized_keys "$user" >/dev/null 2>&1 || true
    local tmp; tmp="$(lsshm_mktemp)"
    local i=0 removed=0 line fp
    while IFS= read -r line; do
        lsshm_access_classify_line "$line"
        if [ "$_ak_kind" = "skip" ]; then
            printf '%s\n' "$line" >>"$tmp"
            continue
        fi
        i=$((i+1))
        fp="$(lsshm_access_fingerprint_line "$_ak_keyline" | awk '{print $2}')"
        if [ "$target" = "$i" ] || { [ -n "$fp" ] && [ "$target" = "$fp" ]; }; then
            removed=1
            continue
        fi
        printf '%s\n' "$line" >>"$tmp"
    done <<EOF
$content
EOF
    if [ "$removed" = "0" ]; then
        lsshm_warn 'No matching key found.'
        return 1
    fi
    lsshm_access_write "$user" "$file" "$tmp"
    lsshm_ok 'Key removed for %s.' "$user"
}

# Repair ownership and permissions of the user's .ssh directory.
lsshm_access_repair() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local home; home="$(lsshm_user_home "$user")"
    local ssh_dir="$home/.ssh"
    local uid gid
    uid="$(id -u "$user" 2>/dev/null || echo 0)"
    gid="$(id -g "$user" 2>/dev/null || echo 0)"

    [ -d "$ssh_dir" ] || { lsshm_warn '%s does not exist.' "$ssh_dir"; return 0; }

    local runner=""
    [ -w "$ssh_dir" ] || runner="lsshm_run_privileged"

    $runner chown -R "$uid:$gid" "$ssh_dir"
    $runner chmod 700 "$ssh_dir"
    [ -e "$ssh_dir/authorized_keys" ] && $runner chmod 600 "$ssh_dir/authorized_keys"
    local f
    for f in "$ssh_dir"/id_* "$ssh_dir"/*.pub; do
        [ -e "$f" ] || continue
        case "$f" in
            *.pub) $runner chmod 644 "$f" ;;
            *)     $runner chmod 600 "$f" ;;
        esac
    done
    lsshm_ok 'Permissions repaired for %s:' "$user"
    lsshm_info '  .ssh 700, authorized_keys 600, private keys 600, public keys 644'
}

# Temporarily disable or re-enable a key by fingerprint or index (same numbering as list).
lsshm_access_disable() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local target="${2:-}"
    local file; file="$(lsshm_access_file "$user")"
    local content; content="$(lsshm_access_read "$file")"
    [ -n "$content" ] || { lsshm_info 'No key to disable.'; return 0; }

    if [ -z "$target" ]; then
        lsshm_access_list "$user"
        target="$(lsshm_prompt "$(lsshm_t 'SHA256 fingerprint or number to disable/re-enable')" '')"
    fi
    [ -n "$target" ] || { lsshm_info 'Cancelled.'; return 0; }

    lsshm_backup_authorized_keys "$user" >/dev/null 2>&1 || true
    local tmp; tmp="$(lsshm_mktemp)"
    local i=0 changed=0 line fp
    while IFS= read -r line; do
        lsshm_access_classify_line "$line"
        if [ "$_ak_kind" = "skip" ]; then
            printf '%s\n' "$line" >>"$tmp"
            continue
        fi
        i=$((i+1))
        fp="$(lsshm_access_fingerprint_line "$_ak_keyline" | awk '{print $2}')"
        if [ "$target" = "$i" ] || { [ -n "$fp" ] && [ "$target" = "$fp" ]; }; then
            if [ "$_ak_kind" = "disabled" ]; then
                printf '%s\n' "$_ak_keyline" >>"$tmp"
            else
                printf '# LSSHM-DISABLED %s\n' "$line" >>"$tmp"
            fi
            changed=1
        else
            printf '%s\n' "$line" >>"$tmp"
        fi
    done <<EOF
$content
EOF
    if [ "$changed" = "0" ]; then
        lsshm_warn 'No matching key found.'
        return 1
    fi
    lsshm_access_write "$user" "$file" "$tmp"
    lsshm_ok 'Key state updated for %s.' "$user"
}

# Detect duplicate keys across the file.
lsshm_access_duplicates() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local file; file="$(lsshm_access_file "$user")"
    local content; content="$(lsshm_access_read "$file")"
    [ -n "$content" ] || { lsshm_info 'No key.'; return 0; }
    local line fp
    printf '%s\n' "$content" | while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        lsshm_access_fingerprint_line "$line" | awk '{print $2}'
    done | sort | uniq -d | while IFS= read -r fp; do
        [ -n "$fp" ] && lsshm_warn 'Duplicate detected: %s' "$fp"
    done
    lsshm_ok 'Duplicate analysis complete.'
}
