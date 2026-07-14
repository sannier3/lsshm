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

# Detect existing key pairs (files with a matching .pub).
lsshm_keys_list() {
    local dir; dir="$(lsshm_keys_dir)"
    printf 'Répertoire : %s\n\n' "$dir"
    if [ ! -d "$dir" ]; then
        lsshm_info "Aucun répertoire ~/.ssh."
        return 0
    fi
    local found=0 pub priv info
    for pub in "$dir"/*.pub; do
        [ -e "$pub" ] || continue
        priv="${pub%.pub}"
        found=$((found+1))
        info="$(ssh-keygen -lf "$pub" 2>/dev/null)"
        printf '%d. %s\n' "$found" "$(basename "$priv")"
        printf '   Clé publique : %s\n' "$pub"
        printf '   Clé privée   : %s\n' "$([ -f "$priv" ] && echo "$priv (présente)" || echo "absente")"
        printf '   Empreinte    : %s\n' "${info:-inconnue}"
    done
    [ "$found" = "0" ] && lsshm_info "Aucune paire de clés détectée."
}

# Generate a new key pair. Default type ED25519.
lsshm_keys_generate() {
    local dir; dir="$(lsshm_keys_dir)"
    mkdir -p "$dir" 2>/dev/null || lsshm_run_privileged mkdir -p "$dir"

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
        lsshm_ok "Clé générée : $path"
        lsshm_info "Clé publique :"
        cat "$path.pub"
    else
        lsshm_error "Échec de la génération."
        return 1
    fi
}

lsshm_keys_inspect() {
    local path="$1"
    [ -n "$path" ] || path="$(lsshm_prompt 'Chemin de la clé' "$(lsshm_keys_dir)/id_ed25519")"
    local pub="$path"
    [ -f "$path.pub" ] && pub="$path.pub"
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
    local path="$1"
    [ -n "$path" ] || path="$(lsshm_prompt 'Chemin de la clé' "$(lsshm_keys_dir)/id_ed25519")"
    local pub="$path"
    [ -f "$path.pub" ] && pub="$path.pub"
    case "$pub" in
        *.pub) ;;
        *)     lsshm_error "Refus d'exporter un fichier non .pub (protection clé privée)."; return 1 ;;
    esac
    [ -f "$pub" ] || { lsshm_error "Clé publique introuvable : $pub"; return 1; }
    lsshm_info "Clé publique ($pub) :"
    cat "$pub"
}

lsshm_keys_passphrase() {
    local path="$1"
    [ -n "$path" ] || path="$(lsshm_prompt 'Chemin de la clé privée' "$(lsshm_keys_dir)/id_ed25519")"
    [ -f "$path" ] || { lsshm_error "Clé privée introuvable : $path"; return 1; }
    lsshm_info "Modification de la phrase secrète de $path"
    ssh-keygen -p -f "$path"
}

lsshm_keys_delete() {
    local path="$1"
    [ -n "$path" ] || path="$(lsshm_prompt 'Chemin de la clé à supprimer' '')"
    [ -n "$path" ] || { lsshm_info "Annulé."; return 0; }
    local priv="$path" pub="$path.pub"
    case "$path" in *.pub) priv="${path%.pub}"; pub="$path" ;; esac

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
