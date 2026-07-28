# shellcheck shell=bash
# =============================================================================
# hosts.sh - remote machines managed through ~/.ssh/config (OPTIONAL feature)
# =============================================================================
# These are outgoing connection targets. LSSHM remains fully usable with no
# host configured.

lsshm_hosts_file() {
    printf '%s/config' "$(lsshm_target_ssh_dir)"
}

lsshm_hosts_list() {
    local file; file="$(lsshm_hosts_file)"
    if [ ! -f "$file" ]; then
        lsshm_info 'No ~/.ssh/config file.'
        return 0
    fi
    lsshm_info 'Registered remote hosts (%s):' "$file"
    local count=0 name hostname
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in *'*'*|*'?'*) continue ;; esac
        count=$((count+1))
        hostname="$(lsshm_hosts_get_field "$name" HostName)"
        printf '  %-20s %s\n' "$name" "${hostname:-}"
    done <<EOF
$(awk 'tolower($1)=="host"{for(i=2;i<=NF;i++)print $i}' "$file")
EOF
    [ "$count" = "0" ] && lsshm_info '  (none)'
}

lsshm_hosts_count() {
    local file; file="$(lsshm_hosts_file)"
    [ -f "$file" ] || { printf '0'; return; }
    awk 'tolower($1)=="host"{for(i=2;i<=NF;i++){if($i!~/[*?]/)c++}}END{print c+0}' "$file"
}

# Get a field value from a Host block in the config file.
lsshm_hosts_get_field() {
    local name="$1" field="$2" file
    file="$(lsshm_hosts_file)"
    [ -f "$file" ] || return 1
    awk -v want="$name" -v f="$(printf '%s' "$field" | tr '[:upper:]' '[:lower:]')" '
        tolower($1)=="host" { inblk=0; for(i=2;i<=NF;i++) if($i==want) inblk=1; next }
        inblk && tolower($1)==f { $1=""; sub(/^ /,""); print; exit }
    ' "$file"
}

lsshm_hosts_exists() {
    local name="$1" file
    file="$(lsshm_hosts_file)"
    [ -f "$file" ] || return 1
    awk -v want="$name" 'tolower($1)=="host"{for(i=2;i<=NF;i++) if($i==want){found=1}} END{exit(found?0:1)}' "$file"
}

lsshm_hosts_add() {
    local file; file="$(lsshm_hosts_file)"
    lsshm_ensure_user_ssh_dir "$LSSHM_CALLING_USER"

    local name hostname user port identity proxyjump
    name="$(lsshm_prompt "$(lsshm_t 'Host alias name')" 'proxmox1')"
    [ -n "$name" ] || { lsshm_error 'Name required.'; return 1; }
    if lsshm_hosts_exists "$name"; then
        lsshm_error "A host named '%s' already exists." "$name"
        return 1
    fi
    hostname="$(lsshm_prompt "$(lsshm_t 'Address (HostName)')" '192.168.100.240')"
    user="$(lsshm_prompt "$(lsshm_t 'User')" 'root')"
    port="$(lsshm_prompt "$(lsshm_t 'Port')" '22')"
    identity="$(lsshm_prompt "$(lsshm_t 'Key file (IdentityFile)')" "$(lsshm_keys_dir)/id_ed25519")"
    proxyjump="$(lsshm_prompt "$(lsshm_t 'ProxyJump (empty = none)')" '')"

    {
        printf '\nHost %s\n' "$name"
        printf '    HostName %s\n' "$hostname"
        printf '    User %s\n' "$user"
        printf '    Port %s\n' "$port"
        printf '    IdentityFile %s\n' "$identity"
        printf '    IdentitiesOnly yes\n'
        [ -n "$proxyjump" ] && printf '    ProxyJump %s\n' "$proxyjump"
    } >>"$file"
    chmod 600 "$file" 2>/dev/null || true
    lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
    lsshm_ok "Host '%s' added to %s" "$name" "$file"
}

lsshm_hosts_delete() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name to delete')" '')"
    [ -n "$name" ] || { lsshm_info 'Cancelled.'; return 0; }
    local file; file="$(lsshm_hosts_file)"
    [ -f "$file" ] || { lsshm_error 'No config file.'; return 1; }
    lsshm_hosts_exists "$name" || { lsshm_error 'Host not found: %s' "$name"; return 1; }

    lsshm_backup_file "$file" "ssh-config" >/dev/null 2>&1 || true
    local tmp; tmp="$(lsshm_mktemp)"
    awk -v want="$name" '
        tolower($1)=="host" {
            skip=0; for(i=2;i<=NF;i++) if($i==want) skip=1;
            if(skip){inblk=1; next} else {inblk=0}
        }
        !inblk { print }
    ' "$file" >"$tmp"
    install -m 0600 "$tmp" "$file"
    lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
    lsshm_ok "Host '%s' deleted." "$name"
}

lsshm_hosts_edit() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name to edit')" '')"
    lsshm_hosts_exists "$name" || { lsshm_error 'Host not found: %s' "$name"; return 1; }
    lsshm_info "Current configuration of '%s':" "$name"
    lsshm_hosts_show "$name"
    lsshm_warn 'Editing replaces the whole block.'
    lsshm_confirm "$(lsshm_t 'Continue?')" no || return 0
    local file snap
    file="$(lsshm_hosts_file)"
    snap="$(lsshm_mktemp)"
    cp -a "$file" "$snap" 2>/dev/null || { lsshm_error 'Unable to back up %s.' "$file"; return 1; }
    lsshm_hosts_delete "$name"
    if ! lsshm_hosts_add; then
        install -m 0600 "$snap" "$file"
        lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
        lsshm_warn "Edit cancelled: host '%s' has been restored." "$name"
        return 1
    fi
}

lsshm_hosts_show() {
    local name="$1"
    printf '  HostName    : %s\n' "$(lsshm_hosts_get_field "$name" HostName)"
    printf '  User        : %s\n' "$(lsshm_hosts_get_field "$name" User)"
    printf '  Port        : %s\n' "$(lsshm_hosts_get_field "$name" Port)"
    printf '  IdentityFile: %s\n' "$(lsshm_hosts_get_field "$name" IdentityFile)"
    printf '  ProxyJump   : %s\n' "$(lsshm_hosts_get_field "$name" ProxyJump)"
}

lsshm_hosts_effective() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name')" '')"
    lsshm_have ssh || { lsshm_error 'ssh not found.'; return 1; }
    lsshm_info 'Effective configuration (ssh -G %s):' "$name"
    ssh -G "$name" 2>/dev/null | grep -Ei '^(hostname|user|port|identityfile|proxyjump) '
}

lsshm_hosts_test() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name to test')" '')"
    local host port
    host="$(lsshm_hosts_get_field "$name" HostName)"; host="${host:-$name}"
    port="$(lsshm_hosts_get_field "$name" Port)"; port="${port:-22}"

    lsshm_info 'Resolving %s...' "$host"
    if lsshm_have getent && getent hosts "$host" >/dev/null 2>&1; then
        lsshm_ok 'DNS resolution succeeded.'
    else
        lsshm_warn 'DNS resolution uncertain.'
    fi

    lsshm_info 'Testing port %s...' "$port"
    if lsshm_have nc && nc -z -w 3 "$host" "$port" 2>/dev/null; then
        lsshm_ok 'Port %s open.' "$port"
    elif (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
        lsshm_ok 'Port %s open.' "$port"
        exec 3>&- 2>/dev/null || true
    else
        lsshm_warn 'Port %s unreachable.' "$port"
    fi

    lsshm_info 'SSH authentication test (BatchMode)...'
    local ssh_err ssh_rc=0
    ssh_err="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes "$name" true 2>&1)" || ssh_rc=$?
    if [ "$ssh_rc" -eq 0 ]; then
        lsshm_ok 'Authentication succeeded.'
        return 0
    fi

    if printf '%s' "$ssh_err" | grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed|Offending .+ key in'; then
        lsshm_warn 'Remote host identification has changed (known_hosts conflict).'
        lsshm_warn 'This can happen after a reinstall, or indicate a MITM risk.'
        if lsshm_confirm "$(lsshm_tf 'Remove the old host key for %s from known_hosts?' "$host")" yes; then
            lsshm_known_hosts_remove "$host" || true
            [ "$host" != "$name" ] && lsshm_known_hosts_remove "$name" || true
            if [ "$port" != "22" ]; then
                lsshm_known_hosts_remove "[${host}]:${port}" || true
            fi
            if lsshm_confirm "$(lsshm_t 'Fetch and accept the new host key now?')" yes; then
                if lsshm_have ssh-keyscan; then
                    local file; file="$(lsshm_known_hosts_file)"
                    mkdir -p "$(dirname "$file")"
                    touch "$file"
                    lsshm_backup_file "$file" "known-hosts" >/dev/null 2>&1 || true
                    if ssh-keyscan -p "$port" "$host" 2>/dev/null >>"$file"; then
                        lsshm_chown_user "$LSSHM_CALLING_USER" "$file"
                        lsshm_ok 'New host key(s) for %s added to known_hosts.' "$host"
                        lsshm_known_hosts_scan "$host" || true
                    else
                        lsshm_error 'Unable to fetch host keys from %s.' "$host"
                    fi
                else
                    lsshm_error 'ssh-keyscan not found.'
                fi
            fi
            lsshm_info 'Re-run the host test after updating known_hosts.'
        fi
        return 1
    fi

    lsshm_warn 'Automatic authentication failed (missing key or password required).'
}

lsshm_hosts_connect() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name')" '')"
    [ -n "$name" ] || return 1
    lsshm_info 'Connecting to %s...' "$name"
    ssh "$name"
}

lsshm_hosts_copy_key() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name')" '')"
    lsshm_have ssh-copy-id || { lsshm_error 'ssh-copy-id not found.'; return 1; }
    local identity; identity="$(lsshm_hosts_get_field "$name" IdentityFile)"
    identity="$(lsshm_expand_user_path "${identity:-$(lsshm_keys_dir)/id_ed25519}")"
    local pub="$identity.pub"
    [ -f "$pub" ] || { lsshm_error 'Public key not found: %s' "$pub"; return 1; }
    lsshm_info 'Copying %s to %s...' "$pub" "$name"
    ssh-copy-id -i "$pub" "$name"
}

lsshm_hosts_revoke_key() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt "$(lsshm_t 'Host name')" '')"
    [ -n "$name" ] || { lsshm_info 'Cancelled.'; return 0; }
    local identity; identity="$(lsshm_hosts_get_field "$name" IdentityFile)"
    identity="$(lsshm_expand_user_path "${identity:-$(lsshm_keys_dir)/id_ed25519}")"
    local pub="$identity.pub"
    [ -f "$pub" ] || { lsshm_error 'Public key not found: %s' "$pub"; return 1; }
    local keytext; keytext="$(awk '{print $2}' "$pub")"
    [ -n "$keytext" ] || { lsshm_error 'Empty public key body.'; return 1; }
    # OpenSSH key bodies are base64; reject anything else before remote use.
    case "$keytext" in
        *[!A-Za-z0-9+/=]*)
            lsshm_error 'Invalid key body (unexpected characters).'
            return 1
            ;;
    esac
    lsshm_warn 'Removing the key on %s (requires authorized access).' "$name"
    lsshm_confirm "$(lsshm_t 'Continue?')" no || return 0
    # Pass the key body as argv ($1): SSH does not forward local env vars.
    # base64-only keytext is safe to embed via printf %q.
    if ssh "$name" "bash -s -- $(printf '%q' "$keytext")" <<'REMOTE'
set -euo pipefail
KEYBLOB="$1"
ak="${HOME}/.ssh/authorized_keys"
[ -f "$ak" ] || { echo "authorized_keys not found" >&2; exit 1; }
tmp="$(mktemp "${TMPDIR:-/tmp}/lsshm-ak.XXXXXX")"
awk -v k="$KEYBLOB" '
{
  keep=1
  for (i=1; i<=NF; i++) if ($i == k) keep=0
  if (keep) print
}' "$ak" >"$tmp"
mv "$tmp" "$ak"
chmod 600 "$ak"
REMOTE
    then
        lsshm_ok 'Key removed on %s.' "$name"
    else
        lsshm_error 'Removal failed.'
        return 1
    fi
}
