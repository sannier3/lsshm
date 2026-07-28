# shellcheck shell=bash
# =============================================================================
# local_keys.sh - keys used by THIS machine to connect ELSEWHERE
# =============================================================================
# These are private/public key pairs in ~/.ssh/id_* used for outgoing SSH
# connections. LSSHM must never transmit or display a private key without an
# explicit warning.

lsshm_keys_dir() {
    lsshm_target_ssh_dir
}

# Fill LSSHM_KEY_PATHS with private-key paths (one per .pub found).
# Must be called in the current shell (not via $(...)): arrays do not survive
# command substitution. Sets LSSHM_KEY_COUNT and returns 0.
lsshm_keys_collect() {
    LSSHM_KEY_PATHS=()
    LSSHM_KEY_COUNT=0
    local dir; dir="$(lsshm_keys_dir)"
    [ -d "$dir" ] || return 0
    local pub priv
    # nullglob-safe: skip the literal "*.pub" when the directory is empty.
    for pub in "$dir"/*.pub; do
        [ -e "$pub" ] || continue
        priv="${pub%.pub}"
        LSSHM_KEY_PATHS+=("$priv")
    done
    LSSHM_KEY_COUNT="${#LSSHM_KEY_PATHS[@]}"
}

# Print a numbered list of key pairs (same numbering as pick).
lsshm_keys_print_numbered() {
    local dir; dir="$(lsshm_keys_dir)"
    lsshm_out 'Directory: %s' "$dir"
    printf '\n'
    lsshm_keys_collect
    if [ "${LSSHM_KEY_COUNT:-0}" = "0" ]; then
        lsshm_info 'No key pair detected.'
        return 1
    fi
    local i=0 priv pub info privlabel
    for priv in "${LSSHM_KEY_PATHS[@]}"; do
        i=$((i+1))
        pub="$priv.pub"
        info="$(ssh-keygen -lf "$pub" 2>/dev/null)"
        if [ -f "$priv" ]; then
            privlabel="$priv ($(lsshm_t 'present'))"
        else
            privlabel="$(lsshm_t 'absent')"
        fi
        printf '%d. %s\n' "$i" "$(basename "$priv")"
        lsshm_out '   Public key  : %s' "$pub"
        lsshm_out '   Private key : %s' "$privlabel"
        lsshm_out '   Fingerprint : %s' "${info:-$(lsshm_t 'unknown')}"
    done
    return 0
}

# Detect existing key pairs (files with a matching .pub).
lsshm_keys_list() {
    lsshm_keys_print_numbered || true
}

# Interactive picker: list keys, ask for a number (or accept an existing path).
# Usage: path="$(lsshm_keys_pick 'Prompt' [require_private=0|1])"
# Echoes the private-key path (without .pub), or empty on cancel.
lsshm_keys_pick() {
    local prompt="${1:-Choose a key}"
    local require_priv="${2:-0}"
    local given="${3:-}"

    # Non-interactive / explicit path argument.
    if [ -n "$given" ]; then
        local path="$given"
        case "$path" in *.pub) path="${path%.pub}" ;; esac
        if [ "$require_priv" = "1" ] && [ ! -f "$path" ]; then
            lsshm_error 'Private key not found: %s' "$path" >&2
            return 1
        fi
        if [ ! -f "$path.pub" ] && [ ! -f "$path" ]; then
            lsshm_error 'Key not found: %s' "$given" >&2
            return 1
        fi
        printf '%s' "$path"
        return 0
    fi

    # List on stderr so only the selected path is captured on stdout.
    if ! lsshm_keys_print_numbered >&2; then
        return 1
    fi
    printf '\n' >&2
    local choice; choice="$(lsshm_prompt "$(lsshm_tf '%s (number)' "$(lsshm_t "$prompt")")" '')"
    if [ -z "$choice" ]; then
        lsshm_info 'Cancelled.' >&2
        return 1
    fi

    # Allow typing a path as fallback.
    if [ -f "$choice" ] || [ -f "$choice.pub" ]; then
        case "$choice" in *.pub) choice="${choice%.pub}" ;; esac
        printf '%s' "$choice"
        return 0
    fi

    case "$choice" in
        ''|*[!0-9]*)
            lsshm_error 'Invalid choice: %s' "$choice" >&2
            return 1
            ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#LSSHM_KEY_PATHS[@]}" ]; then
        lsshm_error 'Number out of range (1-%s).' "${#LSSHM_KEY_PATHS[@]}" >&2
        return 1
    fi

    local path="${LSSHM_KEY_PATHS[$((choice-1))]}"
    if [ "$require_priv" = "1" ] && [ ! -f "$path" ]; then
        lsshm_error 'Private key missing for %s.' "$(basename "$path")" >&2
        return 1
    fi
    printf '%s' "$path"
    return 0
}

# Generate a new key pair. Default type ED25519.
lsshm_keys_generate() {
    local dir; dir="$(lsshm_keys_dir)"
    lsshm_ensure_user_ssh_dir "$LSSHM_CALLING_USER"

    local type; type="$(lsshm_prompt "$(lsshm_t 'Key type (ed25519/rsa)')" 'ed25519')"
    case "$type" in
        ed25519|ED25519) type="ed25519" ;;
        rsa|RSA)         type="rsa" ;;
        *)               lsshm_warn 'Unknown type, using ed25519.'; type="ed25519" ;;
    esac

    local default_name="id_$type"
    local name; name="$(lsshm_prompt "$(lsshm_t 'File name')" "$default_name")"
    local path="$dir/$name"

    if [ -e "$path" ]; then
        lsshm_warn 'The file %s already exists.' "$path"
        lsshm_confirm "$(lsshm_t 'Overwrite?')" no || { lsshm_info 'Cancelled.'; return 1; }
    fi

    local comment; comment="$(lsshm_prompt "$(lsshm_t 'Comment')" "$LSSHM_CALLING_USER@$(hostname 2>/dev/null || echo host)")"

    local args=(-t "$type" -f "$path" -C "$comment")
    [ "$type" = "rsa" ] && args+=(-b 4096)

    lsshm_info "ssh-keygen ${args[*]}"
    lsshm_info 'A passphrase is strongly recommended.'
    if ssh-keygen "${args[@]}"; then
        chmod 600 "$path" 2>/dev/null || true
        chmod 644 "$path.pub" 2>/dev/null || true
        lsshm_chown_user "$LSSHM_CALLING_USER" "$path" "$path.pub"
        lsshm_ok 'Key generated: %s (user %s)' "$path" "$LSSHM_CALLING_USER"
        lsshm_info 'Public key:'
        cat "$path.pub"
    else
        lsshm_error 'Generation failed.'
        return 1
    fi
}

lsshm_keys_inspect() {
    local path
    path="$(lsshm_keys_pick 'Key to inspect' 0 "${1:-}")" || return 1
    local pub="$path.pub"
    [ -f "$pub" ] || pub="$path"
    if [ ! -f "$pub" ]; then
        lsshm_error 'File not found: %s' "$pub"
        return 1
    fi
    lsshm_info 'Fingerprint:'
    ssh-keygen -lf "$pub"
    lsshm_info 'Random art:'
    ssh-keygen -lvf "$pub" 2>/dev/null | tail -n +1 || true
}

lsshm_keys_export() {
    local path
    path="$(lsshm_keys_pick 'Key to export' 0 "${1:-}")" || return 1
    local pub="$path.pub"
    if [ ! -f "$pub" ]; then
        lsshm_error 'Public key not found: %s' "$pub"
        return 1
    fi
    lsshm_info 'Public key (%s):' "$pub"
    cat "$pub"
}

lsshm_keys_passphrase() {
    local path
    path="$(lsshm_keys_pick 'Key whose passphrase to change' 1 "${1:-}")" || return 1
    lsshm_info 'Changing the passphrase of %s' "$path"
    ssh-keygen -p -f "$path"
}

lsshm_keys_delete() {
    local path
    path="$(lsshm_keys_pick 'Key to delete' 0 "${1:-}")" || return 1
    local priv="$path" pub="$path.pub"

    if [ ! -e "$priv" ] && [ ! -e "$pub" ]; then
        lsshm_error 'No key file found for: %s' "$path"
        return 1
    fi
    lsshm_warn 'Deleting the key pair:'
    [ -e "$priv" ] && printf '  %s\n' "$priv"
    [ -e "$pub" ]  && printf '  %s\n' "$pub"
    lsshm_confirm "$(lsshm_t 'A backup will be created. Confirm deletion?')" no || { lsshm_info 'Cancelled.'; return 0; }

    [ -e "$priv" ] && lsshm_backup_file "$priv" "privkey" >/dev/null 2>&1 || true
    [ -e "$pub" ]  && lsshm_backup_file "$pub" "pubkey" >/dev/null 2>&1 || true
    rm -f "$priv" "$pub"
    lsshm_ok 'Key pair deleted (backup kept).'
}
