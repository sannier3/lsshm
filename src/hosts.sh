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
        lsshm_info "Aucun fichier ~/.ssh/config."
        return 0
    fi
    lsshm_info "Machines distantes enregistrées ($file) :"
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
    [ "$count" = "0" ] && lsshm_info "  (aucune)"
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
    local dir; dir="$(dirname "$file")"
    mkdir -p "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true

    local name hostname user port identity proxyjump
    name="$(lsshm_prompt 'Nom (alias) de la machine' 'proxmox1')"
    [ -n "$name" ] || { lsshm_error "Nom requis."; return 1; }
    if lsshm_hosts_exists "$name"; then
        lsshm_error "Un hôte nommé '$name' existe déjà."
        return 1
    fi
    hostname="$(lsshm_prompt 'Adresse (HostName)' '192.168.100.240')"
    user="$(lsshm_prompt 'Utilisateur' 'root')"
    port="$(lsshm_prompt 'Port' '22')"
    identity="$(lsshm_prompt 'Fichier de clé (IdentityFile)' "$(lsshm_keys_dir)/id_ed25519")"
    proxyjump="$(lsshm_prompt 'ProxyJump (vide = aucun)' '')"

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
    lsshm_ok "Hôte '$name' ajouté à $file"
}

lsshm_hosts_delete() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte à supprimer' '')"
    [ -n "$name" ] || { lsshm_info "Annulé."; return 0; }
    local file; file="$(lsshm_hosts_file)"
    [ -f "$file" ] || { lsshm_error "Aucun fichier config."; return 1; }
    lsshm_hosts_exists "$name" || { lsshm_error "Hôte introuvable : $name"; return 1; }

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
    lsshm_ok "Hôte '$name' supprimé."
}

lsshm_hosts_edit() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte à modifier' '')"
    lsshm_hosts_exists "$name" || { lsshm_error "Hôte introuvable : $name"; return 1; }
    lsshm_info "Configuration actuelle de '$name' :"
    lsshm_hosts_show "$name"
    lsshm_warn "L'édition remplace le bloc complet."
    lsshm_confirm "Continuer ?" no || return 0
    lsshm_hosts_delete "$name"
    lsshm_hosts_add
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
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte' '')"
    lsshm_have ssh || { lsshm_error "ssh introuvable."; return 1; }
    lsshm_info "Configuration effective (ssh -G $name) :"
    ssh -G "$name" 2>/dev/null | grep -Ei '^(hostname|user|port|identityfile|proxyjump) '
}

lsshm_hosts_test() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte à tester' '')"
    local host port
    host="$(lsshm_hosts_get_field "$name" HostName)"; host="${host:-$name}"
    port="$(lsshm_hosts_get_field "$name" Port)"; port="${port:-22}"

    lsshm_info "Test de résolution de $host..."
    if lsshm_have getent && getent hosts "$host" >/dev/null 2>&1; then
        lsshm_ok "Résolution DNS réussie."
    else
        lsshm_warn "Résolution DNS incertaine."
    fi

    lsshm_info "Test du port $port..."
    if lsshm_have nc && nc -z -w 3 "$host" "$port" 2>/dev/null; then
        lsshm_ok "Port $port ouvert."
    elif (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
        lsshm_ok "Port $port ouvert."
        exec 3>&- 2>/dev/null || true
    else
        lsshm_warn "Port $port injoignable."
    fi

    lsshm_info "Test d'authentification SSH (BatchMode)..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$name" true 2>/dev/null; then
        lsshm_ok "Authentification réussie."
    else
        lsshm_warn "Authentification non automatique (clé manquante ou mot de passe requis)."
    fi
}

lsshm_hosts_connect() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte' '')"
    [ -n "$name" ] || return 1
    lsshm_info "Connexion à $name..."
    ssh "$name"
}

lsshm_hosts_copy_key() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte' '')"
    lsshm_have ssh-copy-id || { lsshm_error "ssh-copy-id introuvable."; return 1; }
    local identity; identity="$(lsshm_hosts_get_field "$name" IdentityFile)"
    identity="${identity:-$(lsshm_keys_dir)/id_ed25519}"
    local pub="$identity.pub"
    [ -f "$pub" ] || { lsshm_error "Clé publique introuvable : $pub"; return 1; }
    lsshm_info "Copie de $pub vers $name..."
    ssh-copy-id -i "$pub" "$name"
}

lsshm_hosts_revoke_key() {
    local name="$1"
    [ -n "$name" ] || name="$(lsshm_prompt 'Nom de l’hôte' '')"
    [ -n "$name" ] || { lsshm_info "Annulé."; return 0; }
    local identity; identity="$(lsshm_hosts_get_field "$name" IdentityFile)"
    identity="${identity:-$(lsshm_keys_dir)/id_ed25519}"
    # Expand a leading ~/ in IdentityFile (literal prefix, not shell tilde expansion).
    if [ "${identity#~/}" != "$identity" ]; then
        identity="$HOME/${identity#~/}"
    fi
    local pub="$identity.pub"
    [ -f "$pub" ] || { lsshm_error "Clé publique introuvable : $pub"; return 1; }
    local keytext; keytext="$(awk '{print $2}' "$pub")"
    [ -n "$keytext" ] || { lsshm_error "Corps de clé publique vide."; return 1; }
    # OpenSSH key bodies are base64; reject anything else before remote use.
    case "$keytext" in
        *[!A-Za-z0-9+/=]*)
            lsshm_error "Corps de clé invalide (caractères inattendus)."
            return 1
            ;;
    esac
    lsshm_warn "Retrait de la clé sur $name (nécessite un accès autorisé)."
    lsshm_confirm "Continuer ?" no || return 0
    # Exact field match via awk (not grep regex). Key passed as env, not shell-interpolated.
    if KEYBLOB="$keytext" ssh "$name" 'bash -s' <<'REMOTE'
set -euo pipefail
ak="${HOME}/.ssh/authorized_keys"
[ -f "$ak" ] || { echo "authorized_keys introuvable" >&2; exit 1; }
tmp="$(mktemp "${HOME}/.ssh/authorized_keys.lsshm.XXXXXX")"
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
        lsshm_ok "Clé retirée sur $name."
    else
        lsshm_error "Échec du retrait."
        return 1
    fi
}
