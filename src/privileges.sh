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

# Run a command that requires root. Uses sudo only when necessary.
lsshm_run_privileged() {
    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        "$@"
    elif [ -n "$LSSHM_SUDO" ]; then
        lsshm_note "Privilèges requis: sudo $*"
        sudo "$@"
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

# Show the sudo context and let the user choose which user's keys to manage.
lsshm_resolve_target_user() {
    # Explicit --user always wins.
    if [ -n "${LSSHM_TARGET_USER:-}" ]; then
        LSSHM_CALLING_USER="$LSSHM_TARGET_USER"
        return 0
    fi
    # Only prompt when running under sudo with a distinct original user.
    if [ "$LSSHM_IS_ROOT" = "1" ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        if ! lsshm_is_interactive; then
            LSSHM_CALLING_USER="$SUDO_USER"
            return 0
        fi
        printf '\n%s est exécuté avec sudo.\n' "$LSSHM_NAME"
        printf 'Utilisateur appelant  : %s\n' "$SUDO_USER"
        printf 'Utilisateur privilégié: root\n\n'
        printf 'Les clés personnelles de quel utilisateur faut-il gérer ?\n'
        printf '  1. %s\n' "$SUDO_USER"
        printf '  2. root\n'
        printf '  3. Un autre utilisateur\n'
        local choice; choice="$(lsshm_prompt 'Choix' '1')"
        case "$choice" in
            2) LSSHM_CALLING_USER="root" ;;
            3) LSSHM_CALLING_USER="$(lsshm_prompt 'Nom d’utilisateur' "$SUDO_USER")" ;;
            *) LSSHM_CALLING_USER="$SUDO_USER" ;;
        esac
    fi
}
