# shellcheck shell=bash
# =============================================================================
# server_config.sh - sshd_config parsing, effective values, managed drop-in
# =============================================================================

LSSHM_SSHD_CONFIG="/etc/ssh/sshd_config"
LSSHM_MANAGED_CONF="/etc/ssh/sshd_config.d/00-lsshm.conf"

LSSHM_MANAGED_HEADER="# Managed by LSSHM
# Local SSH Manager
# Manual changes may be overwritten."

# --- validation --------------------------------------------------------------

# sshd -t : validate configuration. Returns non-zero on error.
lsshm_server_config_test() {
    if [ -z "${LSSHM_SSHD_BIN:-}" ]; then
        lsshm_warn "Binaire sshd introuvable : validation impossible."
        return 0
    fi
    local out
    if out="$(lsshm_run_privileged "$LSSHM_SSHD_BIN" -t 2>&1)"; then
        return 0
    fi
    lsshm_error "sshd -t a signalé une erreur :"
    printf '%s\n' "$out" >&2
    return 1
}

# sshd -T : dump the effective configuration.
lsshm_server_config_dump() {
    [ -n "${LSSHM_SSHD_BIN:-}" ] || return 1
    lsshm_run_privileged "$LSSHM_SSHD_BIN" -T 2>/dev/null
}

# Effective value of a directive (lowercase key). Falls back to file parsing
# when sshd -T is unavailable.
lsshm_server_config_effective_value() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    local dump val
    dump="$(lsshm_server_config_dump)"
    if [ -n "$dump" ]; then
        val="$(printf '%s\n' "$dump" | awk -v k="$key" 'tolower($1)==k {sub($1 FS,""); print; exit}')"
        [ -n "$val" ] && { printf '%s' "$val"; return 0; }
    fi
    # Fallback: first matching non-comment line across config + includes.
    lsshm_config_parse_value "$key"
}

# Parse a directive value directly from files (first occurrence wins, like sshd).
lsshm_config_parse_value() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    local files; files="$(lsshm_config_effective_files)"
    local f val=""
    while IFS= read -r f; do
        [ -r "$f" ] || continue
        val="$(awk -v k="$key" '
            { line=$0; sub(/#.*/,"",line);
              n=split(line,a," ");
              if (n>=2 && tolower(a[1])==k) { $1=""; sub(/^ /,""); print; exit } }' "$f")"
        [ -n "$val" ] && { printf '%s' "$val"; return 0; }
    done <<EOF
$files
EOF
    printf ''
}

# Ordered list of configuration files: main file, then Include targets in
# lexical order (a simplified model of OpenSSH include handling).
lsshm_config_effective_files() {
    [ -r "$LSSHM_SSHD_CONFIG" ] || { printf '%s\n' "$LSSHM_SSHD_CONFIG"; return; }
    local line trimmed keyword rest pattern g
    # Emit files in the order they are referenced in the main file, expanding
    # Include directives at the point where they appear. Uses bash string
    # operations only (no per-line subprocess) so it stays fast on any host.
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        keyword="${trimmed%%[[:space:]]*}"
        case "$keyword" in
            [Ii]nclude)
                rest="${trimmed#"$keyword"}"
                rest="${rest#"${rest%%[![:space:]]*}"}"
                for pattern in $rest; do
                    case "$pattern" in
                        /*) : ;;
                        *) pattern="/etc/ssh/$pattern" ;;
                    esac
                    for g in $pattern; do
                        [ -f "$g" ] && printf '%s\n' "$g"
                    done
                done
                ;;
        esac
    done <"$LSSHM_SSHD_CONFIG"
    # The main file itself participates too (directives outside includes).
    printf '%s\n' "$LSSHM_SSHD_CONFIG"
}

# Detect whether the main config defines a directive BEFORE its Include line.
# Such an early definition would win over the managed drop-in.
lsshm_config_defined_before_include() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [ -r "$LSSHM_SSHD_CONFIG" ] || return 1
    awk -v k="$key" '
        BEGIN{seen=0; inc=0}
        {
            line=$0; sub(/#.*/,"",line);
            n=split(line,a," ");
            if (n>=1 && tolower(a[1])=="include") { inc=1 }
            if (!inc && n>=2 && tolower(a[1])==k) { seen=1 }
        }
        END{ exit (seen?0:1) }
    ' "$LSSHM_SSHD_CONFIG"
}

# --- managed drop-in ---------------------------------------------------------

lsshm_managed_ensure_include() {
    # Warn if the main config has no Include for sshd_config.d.
    [ -r "$LSSHM_SSHD_CONFIG" ] || return 0
    if ! grep -Eqi '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' "$LSSHM_SSHD_CONFIG"; then
        lsshm_warn "Le fichier principal n'inclut pas sshd_config.d/."
        lsshm_warn "Le fichier géré par LSSHM pourrait être ignoré."
    fi
}

# Read current value from the managed file only.
lsshm_managed_get() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [ -r "$LSSHM_MANAGED_CONF" ] || return 1
    lsshm_run_privileged awk -v k="$key" '
        { n=split($0,a," "); if (n>=2 && tolower(a[1])==k){ $1=""; sub(/^ /,""); print; exit } }' \
        "$LSSHM_MANAGED_CONF" 2>/dev/null
}

# Upsert a directive into the managed drop-in file and validate.
# Usage: lsshm_managed_set KEY VALUE
lsshm_managed_set() {
    local key="$1" value="$2"
    lsshm_require_root
    lsshm_managed_ensure_include

    if lsshm_config_defined_before_include "$key"; then
        lsshm_warn "'$key' est défini dans $LSSHM_SSHD_CONFIG avant l'Include."
        lsshm_warn "Cette valeur prévaudra sur le fichier géré par LSSHM."
        if lsshm_confirm "Commenter cette définition dans le fichier principal ?" no; then
            lsshm_config_comment_directive "$key"
        fi
    fi

    local tmp; tmp="$(lsshm_mktemp)"
    # Start from existing managed file or a fresh header.
    if lsshm_run_privileged test -f "$LSSHM_MANAGED_CONF"; then
        lsshm_run_privileged cat "$LSSHM_MANAGED_CONF" >"$tmp" 2>/dev/null || true
    fi
    if [ ! -s "$tmp" ]; then
        printf '%s\n\n' "$LSSHM_MANAGED_HEADER" >"$tmp"
    fi

    # Remove any existing line for this key, then append the new value.
    local tmp2; tmp2="$(lsshm_mktemp)"
    awk -v k="$key" '
        { n=split($0,a," "); if (n>=1 && tolower(a[1])==tolower(k)) next; print }
    ' "$tmp" >"$tmp2"
    printf '%s %s\n' "$key" "$value" >>"$tmp2"

    # Install atomically with correct permissions, then validate.
    lsshm_backup_file "$LSSHM_MANAGED_CONF" "managed-conf" >/dev/null 2>&1 || true
    lsshm_run_privileged install -m 0644 -o root -g root "$tmp2" "$LSSHM_MANAGED_CONF"

    if ! lsshm_server_config_test; then
        lsshm_error "Nouvelle configuration invalide : annulation."
        lsshm_run_privileged install -m 0644 "$tmp" "$LSSHM_MANAGED_CONF" 2>/dev/null || true
        return 1
    fi
    lsshm_ok "Directive appliquée : $key $value"

    # Confirm the effective runtime value matches the intended choice.
    local eff_key eff_val norm_eff norm_want
    eff_key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
    eff_val="$(lsshm_server_config_effective_value "$eff_key")"
    if [ -n "$eff_val" ]; then
        norm_eff="$(printf '%s' "$eff_val" | tr '[:upper:]' '[:lower:]')"
        norm_want="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        case "$eff_key" in
            permitrootlogin)
                [ "$norm_eff" = "without-password" ] && norm_eff="prohibit-password"
                ;;
        esac
        if [ "$norm_eff" != "$norm_want" ]; then
            lsshm_warn "Valeur effective (sshd -T) : $eff_val"
            lsshm_warn "Attendu : $value - une autre définition peut encore prévaloir."
        fi
    fi
    return 0
}

# Comment out a directive in the main config (with backup).
lsshm_config_comment_directive() {
    local key="$1"
    lsshm_backup_file "$LSSHM_SSHD_CONFIG" "main-config" >/dev/null 2>&1 || true
    local tmp; tmp="$(lsshm_mktemp)"
    lsshm_run_privileged awk -v k="$key" '
        { n=split($0,a," ");
          if (n>=2 && tolower(a[1])==tolower(k) && a[1] !~ /^#/)
              print "# LSSHM disabled: " $0;
          else print }
    ' "$LSSHM_SSHD_CONFIG" >"$tmp"
    lsshm_run_privileged install -m 0644 "$tmp" "$LSSHM_SSHD_CONFIG"
}

# --- human-readable directives ----------------------------------------------

lsshm_rootlogin_label() {
    case "$1" in
        no)                   printf 'interdit' ;;
        prohibit-password|without-password) printf 'clé uniquement' ;;
        yes)                  printf 'clé ou mot de passe' ;;
        forced-commands-only) printf 'commandes imposées' ;;
        "")                   printf 'non défini' ;;
        *)                    printf '%s' "$1" ;;
    esac
}

lsshm_set_root_login() {
    lsshm_header
    printf 'Connexion SSH de root\n\n'
    printf '  1. Interdire totalement root\n'
    printf '  2. Autoriser root uniquement avec une clé\n'
    printf '  3. Autoriser root avec une clé ou un mot de passe\n'
    printf '  4. Autoriser root uniquement pour des commandes imposées\n\n'
    printf 'Recommandation : autoriser root uniquement avec une clé,\n'
    printf 'ou utiliser un utilisateur normal possédant sudo.\n\n'
    local choice; choice="$(lsshm_prompt 'Choix' '2')"
    local value=""
    case "$choice" in
        1) value="no" ;;
        2) value="prohibit-password" ;;
        3) value="yes" ;;
        4) value="forced-commands-only" ;;
        *) lsshm_info "Aucun changement."; return 0 ;;
    esac
    lsshm_apply_dangerous_change "PermitRootLogin" "$value" "modification de l'accès root"
}

lsshm_set_password_auth() {
    local cur; cur="$(lsshm_server_config_effective_value passwordauthentication)"
    lsshm_info "Authentification par mot de passe actuelle : $(lsshm_yesno_label "$cur")"
    if lsshm_confirm "Autoriser l'authentification par mot de passe ?" no; then
        lsshm_managed_set "PasswordAuthentication" "yes" && lsshm_server_reload
    else
        lsshm_warn "Désactiver les mots de passe peut vous verrouiller sans clé valide."
        lsshm_apply_dangerous_change "PasswordAuthentication" "no" "désactivation des mots de passe"
    fi
}

lsshm_set_pubkey_auth() {
    if lsshm_confirm "Autoriser l'authentification par clé publique ?" yes; then
        lsshm_managed_set "PubkeyAuthentication" "yes" && lsshm_server_reload
    else
        lsshm_managed_set "PubkeyAuthentication" "no" && lsshm_server_reload
    fi
}

lsshm_set_port() {
    local cur; cur="$(lsshm_server_config_effective_value port)"; cur="${cur:-22}"
    local port; port="$(lsshm_prompt 'Nouveau port SSH' "$cur")"
    case "$port" in
        ''|*[!0-9]*) lsshm_error "Port invalide."; return 1 ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        lsshm_error "Port hors plage (1-65535)."; return 1
    fi
    lsshm_warn "Vérifiez votre pare-feu avant de changer le port."
    lsshm_apply_dangerous_change "Port" "$port" "changement du port"
}

lsshm_set_allow_users() {
    local cur; cur="$(lsshm_server_config_effective_value allowusers)"
    lsshm_info "AllowUsers actuel : ${cur:-non défini}"
    local users; users="$(lsshm_prompt 'Utilisateurs autorisés (séparés par des espaces, vide = supprimer)' "$cur")"
    if [ -z "$users" ]; then
        lsshm_info "Suppression de AllowUsers non gérée automatiquement (éditez le fichier géré)."
        return 0
    fi
    lsshm_apply_dangerous_change "AllowUsers" "$users" "modification de AllowUsers"
}

lsshm_set_allow_groups() {
    local cur; cur="$(lsshm_server_config_effective_value allowgroups)"
    lsshm_info "AllowGroups actuel : ${cur:-non défini}"
    local groups; groups="$(lsshm_prompt 'Groupes autorisés (séparés par des espaces)' "$cur")"
    [ -z "$groups" ] && { lsshm_info "Aucun changement."; return 0; }
    lsshm_apply_dangerous_change "AllowGroups" "$groups" "modification de AllowGroups"
}

# Show the effective configuration (sshd -T) or a helpful message.
lsshm_server_config_show() {
    local dump; dump="$(lsshm_server_config_dump)"
    if [ -n "$dump" ]; then
        printf '%s\n' "$dump" | sort
    else
        lsshm_warn "sshd -T indisponible. Fichiers de configuration détectés :"
        lsshm_config_effective_files
    fi
}
