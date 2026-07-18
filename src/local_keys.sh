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
# Returns the count via stdout when used as: count="$(lsshm_keys_collect)"
lsshm_keys_collect() {
    LSSHM_KEY_PATHS=()
    local dir; dir="$(lsshm_keys_dir)"
    [ -d "$dir" ] || { printf '0'; return 0; }
    local pub priv
    for pub in "$dir"/*.pub; do
        [ -e "$pub" ] || continue
        priv="${pub%.pub}"
        LSSHM_KEY_PATHS+=("$priv")
    done
    printf '%s' "${#LSSHM_KEY_PATHS[@]}"
}

# Print a numbered list of key pairs (same numbering as pick).
lsshm_keys_print_numbered() {
    local dir; dir="$(lsshm_keys_dir)"
    printf 'Répertoire : %s\n\n' "$dir"
    local count; count="$(lsshm_keys_collect)"
    if [ "$count" = "0" ]; then
        lsshm_info "Aucune paire de clés détectée."
        return 1
    fi
    local i=0 priv pub info
    for priv in "${LSSHM_KEY_PATHS[@]}"; do
        i=$((i+1))
        pub="$priv.pub"
        info="$(ssh-keygen -lf "$pub" 2>/dev/null)"
        printf '%d. %s\n' "$i" "$(basename "$priv")"
        printf '   Clé publique : %s\n' "$pub"
        printf '   Clé privée   : %s\n' "$([ -f "$priv" ] && echo "$priv (présente)" || echo "absente")"
        printf '   Empreinte    : %s\n' "${info:-inconnue}"
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
    local prompt="${1:-Choisir une clé}"
    local require_priv="${2:-0}"
    local given="${3:-}"

    # Non-interactive / explicit path argument.
    if [ -n "$given" ]; then
        local path="$given"
        case "$path" in *.pub) path="${path%.pub}" ;; esac
        if [ "$require_priv" = "1" ] && [ ! -f "$path" ]; then
            lsshm_error "Clé privée introuvable : $path" >&2
            return 1
        fi
        if [ ! -f "$path.pub" ] && [ ! -f "$path" ]; then
            lsshm_error "Clé introuvable : $given" >&2
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
    local choice; choice="$(lsshm_prompt "$prompt (numéro)" '')"
    if [ -z "$choice" ]; then
        lsshm_info "Annulé." >&2
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
            lsshm_error "Choix invalide : $choice" >&2
            return 1
            ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#LSSHM_KEY_PATHS[@]}" ]; then
        lsshm_error "Numéro hors plage (1-${#LSSHM_KEY_PATHS[@]})." >&2
        return 1
    fi

    local path="${LSSHM_KEY_PATHS[$((choice-1))]}"
    if [ "$require_priv" = "1" ] && [ ! -f "$path" ]; then
        lsshm_error "Clé privée absente pour $(basename "$path")." >&2
        return 1
    fi
    printf '%s' "$path"
    return 0
}

# Generate a new key pair. Default type ED25519.
lsshm_keys_generate() {
    local dir; dir="$(lsshm_keys_dir)"
    lsshm_ensure_user_ssh_dir "$LSSHM_CALLING_USER"

    local type; type="$(lsshm_prompt 'Type de clé (ed25519/rsa)' 'ed25519')"
    case "$type" in
        ed25519|ED25519) type="ed25519" ;;
        rsa|RSA)         type="rsa" ;;
        *)               lsshm_warn "Type inconnu, utilisation de ed25519."; type="ed25519" ;;
    esac

    local default_name="id_$type"
    local name; name="$(lsshm_prompt 'Nom du fichier' "$default_name")"
    local path="$dir/$name"

    if [ -e "$path" ]; then
        lsshm_warn "Le fichier $path existe déjà."
        lsshm_confirm "Écraser ?" no || { lsshm_info "Annulé."; return 1; }
    fi

    local comment; comment="$(lsshm_prompt 'Commentaire' "$LSSHM_CALLING_USER@$(hostname 2>/dev/null || echo host)")"

    local args=(-t "$type" -f "$path" -C "$comment")
    [ "$type" = "rsa" ] && args+=(-b 4096)

    lsshm_info "ssh-keygen ${args[*]}"
    lsshm_info "Une phrase secrète est fortement recommandée."
    if ssh-keygen "${args[@]}"; then
        chmod 600 "$path" 2>/dev/null || true
        chmod 644 "$path.pub" 2>/dev/null || true
        lsshm_chown_user "$LSSHM_CALLING_USER" "$path" "$path.pub"
        lsshm_ok "Clé générée : $path (utilisateur $LSSHM_CALLING_USER)"
        lsshm_info "Clé publique :"
        cat "$path.pub"
    else
        lsshm_error "Échec de la génération."
        return 1
    fi
}

lsshm_keys_inspect() {
    local path
    path="$(lsshm_keys_pick 'Clé à inspecter' 0 "${1:-}")" || return 1
    local pub="$path.pub"
    [ -f "$pub" ] || pub="$path"
    if [ ! -f "$pub" ]; then
        lsshm_error "Fichier introuvable : $pub"
        return 1
    fi
    lsshm_info "Empreinte :"
    ssh-keygen -lf "$pub"
    lsshm_info "Art aléatoire :"
    ssh-keygen -lvf "$pub" 2>/dev/null | tail -n +1 || true
}

lsshm_keys_export() {
    local path
    path="$(lsshm_keys_pick 'Clé à exporter' 0 "${1:-}")" || return 1
    local pub="$path.pub"
    if [ ! -f "$pub" ]; then
        lsshm_error "Clé publique introuvable : $pub"
        return 1
    fi
    lsshm_info "Clé publique ($pub) :"
    cat "$pub"
}

lsshm_keys_passphrase() {
    local path
    path="$(lsshm_keys_pick 'Clé dont la phrase secrète doit être modifiée' 1 "${1:-}")" || return 1
    lsshm_info "Modification de la phrase secrète de $path"
    ssh-keygen -p -f "$path"
}

lsshm_keys_delete() {
    local path
    path="$(lsshm_keys_pick 'Clé à supprimer' 0 "${1:-}")" || return 1
    local priv="$path" pub="$path.pub"

    if [ ! -e "$priv" ] && [ ! -e "$pub" ]; then
        lsshm_error "Aucun fichier de clé trouvé pour : $path"
        return 1
    fi
    lsshm_warn "Suppression de la paire de clés :"
    [ -e "$priv" ] && printf '  %s\n' "$priv"
    [ -e "$pub" ]  && printf '  %s\n' "$pub"
    lsshm_confirm "Une sauvegarde sera créée. Confirmer la suppression ?" no || { lsshm_info "Annulé."; return 0; }

    [ -e "$priv" ] && lsshm_backup_file "$priv" "privkey" >/dev/null 2>&1 || true
    [ -e "$pub" ]  && lsshm_backup_file "$pub" "pubkey" >/dev/null 2>&1 || true
    rm -f "$priv" "$pub"
    lsshm_ok "Paire de clés supprimée (sauvegarde conservée)."
}
