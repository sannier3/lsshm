# shellcheck shell=bash
# =============================================================================
# platform.sh - detect distribution, package manager, service manager, virt
# =============================================================================

lsshm_detect_platform() {
    LSSHM_OS_ID="unknown"
    LSSHM_OS_NAME="Unknown"
    LSSHM_OS_LIKE=""
    LSSHM_OS_VERSION=""

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        LSSHM_OS_ID="${ID:-unknown}"
        LSSHM_OS_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
        LSSHM_OS_LIKE="${ID_LIKE:-}"
        LSSHM_OS_VERSION="${VERSION_ID:-}"
    fi

    LSSHM_PKG_MGR="$(lsshm_detect_pkg_mgr)"
    LSSHM_SVC_MGR="$(lsshm_detect_svc_mgr)"
    LSSHM_HAS_SYSTEMD=0
    [ "$LSSHM_SVC_MGR" = "systemd" ] && LSSHM_HAS_SYSTEMD=1

    LSSHM_VIRT="$(lsshm_detect_virt)"
    LSSHM_SSHD_BIN="$(lsshm_detect_sshd_bin)"
    LSSHM_SSH_SERVICE="$(lsshm_detect_ssh_service)"
}

lsshm_detect_pkg_mgr() {
    if lsshm_have apt-get; then printf 'apt'
    elif lsshm_have apk; then printf 'apk'
    elif lsshm_have dnf; then printf 'dnf'
    elif lsshm_have yum; then printf 'yum'
    elif lsshm_have pacman; then printf 'pacman'
    elif lsshm_have zypper; then printf 'zypper'
    else printf 'unknown'
    fi
}

lsshm_detect_svc_mgr() {
    if lsshm_have systemctl && [ -d /run/systemd/system ]; then printf 'systemd'
    elif lsshm_have rc-service; then printf 'openrc'
    elif lsshm_have service; then printf 'sysv'
    else printf 'unknown'
    fi
}

lsshm_detect_virt() {
    if lsshm_have systemd-detect-virt; then
        systemd-detect-virt 2>/dev/null || printf 'none'
    elif [ -f /run/systemd/container ]; then
        cat /run/systemd/container 2>/dev/null || printf 'container'
    elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
        printf 'lxc'
    else
        printf 'unknown'
    fi
}

lsshm_detect_sshd_bin() {
    local candidate
    for candidate in /usr/sbin/sshd /usr/bin/sshd /sbin/sshd; do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    if lsshm_have sshd; then
        command -v sshd
        return 0
    fi
    printf ''
}

lsshm_detect_ssh_service() {
    # Debian/Ubuntu use "ssh", most RPM/Arch use "sshd".
    case "$LSSHM_OS_ID" in
        debian|ubuntu|raspbian|linuxmint|pop) printf 'ssh' ;;
        *) printf 'sshd' ;;
    esac
}

lsshm_platform_summary() {
    cat <<EOF
Distribution        : $LSSHM_OS_NAME
Identifiant         : $LSSHM_OS_ID ${LSSHM_OS_VERSION:+($LSSHM_OS_VERSION)}
Gestionnaire paquet : $LSSHM_PKG_MGR
Gestionnaire service: $LSSHM_SVC_MGR
systemd             : $([ "$LSSHM_HAS_SYSTEMD" = 1 ] && echo présent || echo absent)
Virtualisation      : $LSSHM_VIRT
Binaire sshd        : ${LSSHM_SSHD_BIN:-non détecté}
Service SSH         : $LSSHM_SSH_SERVICE
EOF
}

# Is the current distribution supported for full management in this version?
lsshm_platform_is_primary() {
    case "$LSSHM_OS_ID" in
        debian) return 0 ;;
        ubuntu|raspbian|linuxmint|pop) return 0 ;;
        *)
            case " $LSSHM_OS_LIKE " in
                *debian*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}
