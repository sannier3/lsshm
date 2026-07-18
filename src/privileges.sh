# shellcheck shell=bash
# =============================================================================
# privileges.sh - privilege elevation and calling-user resolution
# =============================================================================

lsshm_init_privileges() {
    LSSHM_EUID="$(id -u)"
    LSSHM_IS_ROOT=0
    [ "$LSSHM_EUID" = "0" ] && LSSHM_IS_ROOT=1

    # The user whose personal SSH files should be managed. When invoked through
    # sudo we must not silently manage root's keys.
    LSSHM_CALLING_USER="${LSSHM_TARGET_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"

    if lsshm_have sudo && [ "$LSSHM_IS_ROOT" = "0" ]; then
        LSSHM_SUDO="sudo"
    else
        LSSHM_SUDO=""
    fi
    # Set after a successful sudo -v / privileged auth in this process.
    LSSHM_SUDO_PRIMED="${LSSHM_SUDO_PRIMED:-0}"
}

# Home directory of a given user.
lsshm_user_home() {
    local user="$1" home
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
    if [ -z "$home" ]; then
        if [ "$user" = "${USER:-}" ]; then
            home="$HOME"
        else
            home="/home/$user"
        fi
    fi
    printf '%s' "$home"
}

# The .ssh directory for the managed (calling) user.
lsshm_target_ssh_dir() {
    printf '%s/.ssh' "$(lsshm_user_home "$LSSHM_CALLING_USER")"
}

# Expand a leading ~/ using the managed user's home (not the process $HOME).
lsshm_expand_user_path() {
    local path="$1" user="${2:-$LSSHM_CALLING_USER}"
    if [ "${path#~/}" != "$path" ]; then
        printf '%s/%s' "$(lsshm_user_home "$user")" "${path#~/}"
    else
        printf '%s' "$path"
    fi
}

# True if a non-interactive sudo would succeed (cached credentials).
lsshm_sudo_ready() {
    [ "$LSSHM_IS_ROOT" = "1" ] && return 0
    [ -n "${LSSHM_SUDO:-}" ] || return 1
    sudo -n true >/dev/null 2>&1
}

# Ask for the sudo password at most once per session (when needed).
lsshm_sudo_ensure() {
    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        return 0
    fi
    if [ -z "${LSSHM_SUDO:-}" ]; then
        lsshm_error "Cette opération nécessite les privilèges root, mais sudo est introuvable."
        return 1
    fi
    if lsshm_sudo_ready; then
        LSSHM_SUDO_PRIMED=1
        return 0
    fi
    if ! lsshm_is_interactive || [ ! -t 0 ]; then
        lsshm_error "Authentification sudo requise (session non interactive)."
        return 1
    fi
    lsshm_note "Authentification administrateur (sudo) — une seule fois pour cette session."
    if sudo -v; then
        LSSHM_SUDO_PRIMED=1
        return 0
    fi
    lsshm_error "Échec de l’authentification sudo."
    return 1
}

# Run a command that requires root. Uses sudo only when necessary.
# Authenticates once via lsshm_sudo_ensure, then reuses the sudo ticket.
lsshm_run_privileged() {
    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        "$@"
    elif [ -n "$LSSHM_SUDO" ]; then
        lsshm_sudo_ensure || return 1
        # Do not fall back to an interactive sudo on command failure (that would
        # re-prompt for the password when sshd -t / systemctl simply return 1).
        if lsshm_sudo_ready; then
            sudo -n "$@"
        else
            sudo "$@"
        fi
    else
        lsshm_error "Cette opération nécessite les privilèges root, mais sudo est introuvable."
        return 1
    fi
}

# Run several shell commands under a single sudo (one password prompt max).
# Usage: lsshm_run_privileged_sh 'cmd1 && cmd2'
lsshm_run_privileged_sh() {
    local script="$1"
    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        sh -c "$script"
    elif [ -n "$LSSHM_SUDO" ]; then
        lsshm_sudo_ensure || return 1
        if lsshm_sudo_ready; then
            sudo -n sh -c "$script"
        else
            sudo sh -c "$script"
        fi
    else
        lsshm_error "Cette opération nécessite les privilèges root, mais sudo est introuvable."
        return 1
    fi
}

# True if we can obtain root (already root or sudo available).
lsshm_can_elevate() {
    [ "$LSSHM_IS_ROOT" = "1" ] || [ -n "$LSSHM_SUDO" ]
}

lsshm_require_root() {
    if ! lsshm_can_elevate; then
        lsshm_die "Opération privilégiée impossible: exécutez LSSHM en root ou installez sudo."
    fi
}

# Validate and set the user whose personal SSH files are managed.
lsshm_set_target_user() {
    local user="$1"
    if [ -z "$user" ]; then
        lsshm_error "Nom d’utilisateur vide."
        return 1
    fi
    if ! lsshm_user_exists "$user"; then
        lsshm_error "Utilisateur inconnu : $user"
        return 1
    fi
    LSSHM_CALLING_USER="$user"
    LSSHM_TARGET_USER="$user"
    lsshm_ok "Utilisateur administré : $LSSHM_CALLING_USER ($(lsshm_user_home "$LSSHM_CALLING_USER")/.ssh)"
}

# Ensure ~/.ssh exists with correct ownership for a target user (root admin case).
lsshm_ensure_user_ssh_dir() {
    local user="${1:-$LSSHM_CALLING_USER}"
    local home ssh_dir uid gid
    home="$(lsshm_user_home "$user")"
    ssh_dir="$home/.ssh"
    uid="$(id -u "$user" 2>/dev/null || echo 0)"
    gid="$(id -g "$user" 2>/dev/null || echo 0)"

    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$uid:$gid" "$ssh_dir"
    elif mkdir -p "$ssh_dir" 2>/dev/null; then
        chmod 700 "$ssh_dir" 2>/dev/null || true
    else
        lsshm_run_privileged mkdir -p "$ssh_dir"
        lsshm_run_privileged chmod 700 "$ssh_dir"
        lsshm_run_privileged chown "$uid:$gid" "$ssh_dir"
    fi
}

# chown paths to a login user when we are root (no-op otherwise).
lsshm_chown_user() {
    local user="$1"
    shift
    [ "$LSSHM_IS_ROOT" = "1" ] || return 0
    [ "$#" -gt 0 ] || return 0
    local uid gid
    uid="$(id -u "$user" 2>/dev/null || echo 0)"
    gid="$(id -g "$user" 2>/dev/null || echo 0)"
    chown "$uid:$gid" "$@"
}

# Interactive picker: numbered login users (+ root), or typed name.
lsshm_pick_target_user() {
    local default="${1:-$LSSHM_CALLING_USER}"
    local -a names=()
    local name uid home i=0

    printf '\nUtilisateurs locaux disponibles :\n' >&2
    while IFS=: read -r name uid home; do
        [ -n "$name" ] || continue
        i=$((i + 1))
        names+=("$name")
        printf '  %d. %-16s uid=%-6s %s\n' "$i" "$name" "$uid" "$home" >&2
    done <<EOF
$(lsshm_users_list)
EOF

    if [ "$i" -eq 0 ]; then
        lsshm_error "Aucun utilisateur local détecté."
        return 1
    fi

    local choice
    choice="$(lsshm_prompt "Utilisateur à administrer (numéro ou nom)" "$default")"
    [ -n "$choice" ] || return 1

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
            lsshm_error "Numéro hors plage (1-${#names[@]})."
            return 1
        fi
        choice="${names[$((choice - 1))]}"
    fi

    lsshm_set_target_user "$choice"
}

# Resolve which user's personal SSH files to manage (keys, access, hosts).
lsshm_resolve_target_user() {
    # Explicit --user always wins.
    if [ -n "${LSSHM_TARGET_USER:-}" ]; then
        if ! lsshm_user_exists "$LSSHM_TARGET_USER"; then
            lsshm_die "Utilisateur inconnu : $LSSHM_TARGET_USER"
        fi
        LSSHM_CALLING_USER="$LSSHM_TARGET_USER"
        return 0
    fi

    # Non-interactive: prefer the original sudo user when present.
    if ! lsshm_is_interactive; then
        if [ "$LSSHM_IS_ROOT" = "1" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            LSSHM_CALLING_USER="$SUDO_USER"
        fi
        return 0
    fi

    # Interactive root (sudo or direct login): choose the managed user.
    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            printf '\n%s est exécuté avec sudo.\n' "$LSSHM_NAME"
            printf 'Utilisateur appelant  : %s\n' "$SUDO_USER"
            printf 'Utilisateur privilégié: root\n\n'
            printf 'Les fichiers SSH personnels de quel utilisateur faut-il gérer ?\n'
            printf '  1. %s (recommandé)\n' "$SUDO_USER"
            printf '  2. root\n'
            printf '  3. Choisir un autre utilisateur\n'
            local choice; choice="$(lsshm_prompt 'Choix' '1')"
            case "$choice" in
                2) lsshm_set_target_user "root" || LSSHM_CALLING_USER="root" ;;
                3) lsshm_pick_target_user "$SUDO_USER" || LSSHM_CALLING_USER="$SUDO_USER" ;;
                *) lsshm_set_target_user "$SUDO_USER" || LSSHM_CALLING_USER="$SUDO_USER" ;;
            esac
        else
            # Direct root session (Debian LXC, console root, etc.).
            printf '\n%s est exécuté en root.\n' "$LSSHM_NAME"
            printf 'Vous pouvez administrer le SSH d’un autre utilisateur (clés, accès, hosts).\n\n'
            printf 'Les fichiers SSH personnels de quel utilisateur faut-il gérer ?\n'
            printf '  1. root\n'
            printf '  2. Choisir un autre utilisateur\n'
            local choice; choice="$(lsshm_prompt 'Choix' '2')"
            case "$choice" in
                1) lsshm_set_target_user "root" || true ;;
                *) lsshm_pick_target_user "root" || lsshm_set_target_user "root" || true ;;
            esac
        fi
    fi
}
