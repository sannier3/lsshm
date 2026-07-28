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
        lsshm_warn 'sshd binary not found: validation not possible.'
        return 0
    fi
    local out
    if out="$(lsshm_run_privileged "$LSSHM_SSHD_BIN" -t 2>&1)"; then
        return 0
    fi
    lsshm_error 'sshd -t reported an error:'
    printf '%s\n' "$out" >&2
    return 1
}

lsshm_server_config_cache_file() {
    printf '%s/sshd-T.cache' "${LSSHM_CACHE_DIR:-${TMPDIR:-/tmp}}"
}

# Invalidate the cached sshd -T dump (call after config changes).
# File-backed so the cache survives dump="$(lsshm_server_config_dump)" subshells.
lsshm_server_config_invalidate_cache() {
    LSSHM_SSHD_T_CACHE=""
    LSSHM_SSHD_T_CACHED=0
    rm -f "$(lsshm_server_config_cache_file)" 2>/dev/null || true
}

# sshd -T : dump the effective configuration (cached).
# Never prompts for a sudo password: uses an existing ticket (sudo -n) or fails
# so the status panel / menu can open without asking for admin credentials.
# Pass "refresh" to force a new privileged dump (may prompt once via sudo -v).
lsshm_server_config_dump() {
    local mode="${1:-}" cache_file dump=""
    [ -n "${LSSHM_SSHD_BIN:-}" ] || return 1
    cache_file="$(lsshm_server_config_cache_file)"

    if [ "$mode" = "refresh" ]; then
        lsshm_server_config_invalidate_cache
        if [ "$LSSHM_IS_ROOT" != "1" ] && [ -n "${LSSHM_SUDO:-}" ]; then
            lsshm_sudo_ensure || return 1
        fi
    fi

    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return 0
    fi
    if [ "${LSSHM_SSHD_T_CACHED:-0}" = "1" ] && [ -n "${LSSHM_SSHD_T_CACHE:-}" ]; then
        printf '%s\n' "$LSSHM_SSHD_T_CACHE"
        return 0
    fi

    if [ "$LSSHM_IS_ROOT" = "1" ]; then
        dump="$("$LSSHM_SSHD_BIN" -T 2>/dev/null)" || return 1
    elif [ -n "${LSSHM_SUDO:-}" ]; then
        # Read-only: never trigger a password prompt here.
        dump="$(sudo -n "$LSSHM_SSHD_BIN" -T 2>/dev/null)" || return 1
    else
        dump="$("$LSSHM_SSHD_BIN" -T 2>/dev/null)" || return 1
    fi

    LSSHM_SSHD_T_CACHE="$dump"
    LSSHM_SSHD_T_CACHED=1
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || true
    printf '%s\n' "$dump" >"$cache_file" 2>/dev/null || true
    printf '%s\n' "$dump"
}

# Effective value of a directive (lowercase key). Falls back to file parsing
# when sshd -T is unavailable (e.g. no sudo credentials yet).
lsshm_server_config_effective_value() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    local dump val
    dump="$(lsshm_server_config_dump)" || dump=""
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
        lsshm_warn 'The main config file does not include sshd_config.d/.'
        lsshm_warn 'The file managed by LSSHM might be ignored.'
    fi
}

# Read current value from the managed file only.
lsshm_managed_get() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    local awk_prog='{ n=split($0,a," "); if (n>=2 && tolower(a[1])==k){ $1=""; sub(/^ /,""); print; exit } }'
    if [ -r "$LSSHM_MANAGED_CONF" ]; then
        awk -v k="$key" "$awk_prog" "$LSSHM_MANAGED_CONF" 2>/dev/null
        return 0
    fi
    [ -e "$LSSHM_MANAGED_CONF" ] || return 1
    lsshm_run_privileged awk -v k="$key" "$awk_prog" "$LSSHM_MANAGED_CONF" 2>/dev/null
}

# Upsert a directive into the managed drop-in file and validate.
# Usage: lsshm_managed_set KEY VALUE
lsshm_managed_set() {
    local key="$1" value="$2"
    lsshm_require_root
    lsshm_managed_ensure_include

    if lsshm_config_defined_before_include "$key"; then
        lsshm_warn "'%s' is defined in %s before the Include." "$key" "$LSSHM_SSHD_CONFIG"
        lsshm_warn 'This value will take precedence over the file managed by LSSHM.'
        if lsshm_confirm "$(lsshm_t 'Comment out this definition in the main file?')" no; then
            lsshm_config_comment_directive "$key"
        fi
    fi

    local tmp; tmp="$(lsshm_mktemp)"
    # Start from existing managed file or a fresh header (one sudo for the read).
    if [ -r "$LSSHM_MANAGED_CONF" ]; then
        cat "$LSSHM_MANAGED_CONF" >"$tmp" 2>/dev/null || true
    elif [ -e "$LSSHM_MANAGED_CONF" ]; then
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
    lsshm_server_config_invalidate_cache

    if ! lsshm_server_config_test; then
        lsshm_error 'New configuration invalid: rolling back.'
        lsshm_run_privileged install -m 0644 "$tmp" "$LSSHM_MANAGED_CONF" 2>/dev/null || true
        lsshm_server_config_invalidate_cache
        return 1
    fi
    lsshm_ok 'Directive applied: %s %s' "$key" "$value"

    # Confirm the effective runtime value matches the intended choice.
    local eff_key eff_val norm_eff norm_want
    eff_key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
    # Prefer a fresh privileged dump when credentials are already warm.
    lsshm_server_config_dump >/dev/null 2>&1 || true
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
            lsshm_warn 'Effective value (sshd -T): %s' "$eff_val"
            lsshm_warn 'Expected: %s - another definition may still take precedence.' "$value"
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
        no)                   lsshm_t 'forbidden' ;;
        prohibit-password|without-password) lsshm_t 'key only' ;;
        yes)                  lsshm_t 'key or password' ;;
        forced-commands-only) lsshm_t 'forced commands only' ;;
        "")                   lsshm_t 'not set' ;;
        *)                    printf '%s' "$1" ;;
    esac
}

lsshm_set_root_login() {
    lsshm_header
    lsshm_out 'SSH root login'; printf '\n'
    lsshm_out '  1. Forbid root entirely'
    lsshm_out '  2. Allow root with a key only'
    lsshm_out '  3. Allow root with a key or a password'
    lsshm_out '  4. Allow root only for forced commands'; printf '\n'
    lsshm_out 'Recommendation: allow root with a key only,'
    lsshm_out 'or use a normal user with sudo.'; printf '\n'
    local choice; choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '2')"
    local value=""
    case "$choice" in
        1) value="no" ;;
        2) value="prohibit-password" ;;
        3) value="yes" ;;
        4) value="forced-commands-only" ;;
        *) lsshm_info 'No change.'; return 0 ;;
    esac
    lsshm_apply_dangerous_change "PermitRootLogin" "$value" "$(lsshm_t 'root access change')"
}

lsshm_set_password_auth() {
    local cur; cur="$(lsshm_server_config_effective_value passwordauthentication)"
    lsshm_info 'Current password authentication: %s' "$(lsshm_yesno_label "$cur")"
    if lsshm_confirm "$(lsshm_t 'Allow password authentication?')" no; then
        lsshm_managed_set "PasswordAuthentication" "yes" && lsshm_server_reload
    else
        lsshm_warn 'Disabling passwords may lock you out without a valid key.'
        lsshm_apply_dangerous_change "PasswordAuthentication" "no" "$(lsshm_t 'disabling passwords')"
    fi
}

lsshm_set_pubkey_auth() {
    if lsshm_confirm "$(lsshm_t 'Allow public key authentication?')" yes; then
        lsshm_managed_set "PubkeyAuthentication" "yes" && lsshm_server_reload
    else
        lsshm_warn 'Disabling key authentication may lock you out.'
        lsshm_apply_dangerous_change "PubkeyAuthentication" "no" "$(lsshm_t 'disabling key authentication')"
    fi
}

lsshm_set_port() {
    local cur; cur="$(lsshm_server_config_effective_value port)"; cur="${cur:-22}"
    local port; port="$(lsshm_prompt "$(lsshm_t 'New SSH port')" "$cur")"
    case "$port" in
        ''|*[!0-9]*) lsshm_error 'Invalid port.'; return 1 ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        lsshm_error 'Port out of range (1-65535).'; return 1
    fi
    lsshm_warn 'Check your firewall before changing the port.'
    lsshm_apply_dangerous_change "Port" "$port" "$(lsshm_t 'port change')"
}

# All effective values for a multi-valued directive (e.g. listenaddress).
lsshm_server_config_effective_values() {
    local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    local dump
    dump="$(lsshm_server_config_dump)" || dump=""
    if [ -n "$dump" ]; then
        printf '%s\n' "$dump" | awk -v k="$key" '
            tolower($1) == k { $1=""; sub(/^ /,""); print }
        '
        return 0
    fi
    return 1
}

# Upsert one or more lines for the same KEY (ListenAddress). Empty values → unset.
lsshm_managed_set_multi() {
    local key="$1"; shift
    local -a values=("$@")
    lsshm_require_root
    lsshm_managed_ensure_include

    if lsshm_config_defined_before_include "$key"; then
        lsshm_warn "'%s' is defined in %s before the Include." "$key" "$LSSHM_SSHD_CONFIG"
        lsshm_warn 'This value will take precedence over the file managed by LSSHM.'
        if lsshm_confirm "$(lsshm_t 'Comment out this definition in the main file?')" no; then
            lsshm_config_comment_directive "$key"
        fi
    fi

    local tmp; tmp="$(lsshm_mktemp)"
    if [ -r "$LSSHM_MANAGED_CONF" ]; then
        cat "$LSSHM_MANAGED_CONF" >"$tmp" 2>/dev/null || true
    elif [ -e "$LSSHM_MANAGED_CONF" ]; then
        lsshm_run_privileged cat "$LSSHM_MANAGED_CONF" >"$tmp" 2>/dev/null || true
    fi
    if [ ! -s "$tmp" ]; then
        printf '%s\n\n' "$LSSHM_MANAGED_HEADER" >"$tmp"
    fi

    local tmp2; tmp2="$(lsshm_mktemp)"
    awk -v k="$key" '
        { n=split($0,a," "); if (n>=1 && tolower(a[1])==tolower(k)) next; print }
    ' "$tmp" >"$tmp2"
    local v
    for v in "${values[@]}"; do
        [ -n "$v" ] || continue
        printf '%s %s\n' "$key" "$v" >>"$tmp2"
    done

    lsshm_backup_file "$LSSHM_MANAGED_CONF" "managed-conf" >/dev/null 2>&1 || true
    lsshm_run_privileged install -m 0644 -o root -g root "$tmp2" "$LSSHM_MANAGED_CONF"
    lsshm_server_config_invalidate_cache

    if ! lsshm_server_config_test; then
        lsshm_error 'New configuration invalid: rolling back.'
        lsshm_run_privileged install -m 0644 "$tmp" "$LSSHM_MANAGED_CONF" 2>/dev/null || true
        lsshm_server_config_invalidate_cache
        return 1
    fi
    if [ "${#values[@]}" -eq 0 ]; then
        lsshm_ok 'Directive removed from managed file: %s' "$key"
    else
        lsshm_ok 'Directive applied: %s (%s)' "$key" "${values[*]}"
    fi
    return 0
}

lsshm_set_address_family() {
    local cur; cur="$(lsshm_server_config_effective_value addressfamily)"; cur="${cur:-any}"
    lsshm_header
    lsshm_out 'SSH address family (AddressFamily)'
    lsshm_out 'Current: %s' "$cur"
    printf '\n'
    lsshm_out '  1. any   (IPv4 + IPv6, OpenSSH default)'
    lsshm_out '  2. inet  (IPv4 only)'
    lsshm_out '  3. inet6 (IPv6 only)'
    printf '\n'
    local choice; choice="$(lsshm_prompt "$(lsshm_t 'Choice')" '1')"
    local value=""
    case "$choice" in
        1) value="any" ;;
        2) value="inet" ;;
        3) value="inet6" ;;
        *) lsshm_info 'No change.'; return 0 ;;
    esac
    lsshm_apply_dangerous_change "AddressFamily" "$value" "$(lsshm_t 'address family change')"
}

lsshm_set_listen_address() {
    local cur=""
    cur="$(lsshm_server_config_effective_values listenaddress | tr '\n' ' ')"
    cur="$(printf '%s' "$cur" | sed 's/[[:space:]]*$//')"
    [ -n "$cur" ] || cur="0.0.0.0 ::"
    lsshm_header
    lsshm_out 'SSH listen addresses (ListenAddress)'
    lsshm_out 'Current: %s' "$cur"
    printf '\n'
    lsshm_out 'Examples: 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::'
    lsshm_out 'Empty input restores OpenSSH defaults (all interfaces).'
    printf '\n'
    local raw; raw="$(lsshm_prompt "$(lsshm_t 'Listen addresses (space-separated)')" "$cur")"
    local -a addrs=()
    local tok
    for tok in $raw; do
        addrs+=("$tok")
    done

    if ! lsshm_can_prompt_tty; then
        lsshm_error 'Sensitive change not possible without an interactive terminal: %s' "$(lsshm_t 'listen address change')"
        return 1
    fi
    lsshm_warn 'Sensitive change: %s' "$(lsshm_t 'listen address change')"
    if ! lsshm_confirm "$(lsshm_t 'Continue with an automatic safety rollback?')" no; then
        lsshm_info 'Cancelled.'
        return 1
    fi

    local archive; archive="$(lsshm_backup_server_config)" || return 1
    if ! lsshm_managed_set_multi "ListenAddress" "${addrs[@]}"; then
        lsshm_error 'Change application cancelled.'
        return 1
    fi

    local confirm_flag="$LSSHM_STATE_DIR/rollback.confirm"
    lsshm_run_privileged rm -f "$confirm_flag" 2>/dev/null || true
    local script; script="$(lsshm_rollback_build_script "$archive" "$confirm_flag" "$LSSHM_ROLLBACK_DELAY")"
    local method; method="$(lsshm_rollback_schedule "$script" "$LSSHM_ROLLBACK_DELAY")"
    lsshm_server_reload || true

    if lsshm_server_port_listening; then
        lsshm_ok 'The SSH port is listening.'
    else
        lsshm_warn 'Unable to confirm the SSH port is listening.'
    fi

    printf '\n'
    lsshm_out 'The new configuration is active.'; printf '\n'
    lsshm_out 'An automatic rollback will occur in %s seconds.' "$LSSHM_ROLLBACK_DELAY"; printf '\n'
    lsshm_out 'Open a second SSH connection before confirming.'; printf '\n'
    lsshm_out '  1. The new connection works'
    lsshm_out '  2. Restore immediately'
    local choice; choice="$(lsshm_prompt_tty "$(lsshm_t 'Choice')" '2')"
    case "$choice" in
        1)
            lsshm_rollback_cancel "$method" "$confirm_flag"
            lsshm_ok 'Automatic rollback cancelled. Change kept.'
            ;;
        *)
            lsshm_warn 'Restoring immediately...'
            lsshm_run_privileged tar -xzf "$archive" -C / 2>/dev/null || true
            lsshm_rollback_cancel "$method" "$confirm_flag"
            lsshm_server_reload || true
            lsshm_ok 'Previous configuration restored.'
            ;;
    esac
}

lsshm_set_allow_users() {
    local cur; cur="$(lsshm_server_config_effective_value allowusers)"
    lsshm_info 'Current AllowUsers: %s' "${cur:-$(lsshm_t 'not set')}"
    local users; users="$(lsshm_prompt "$(lsshm_t 'Allowed users (space-separated, empty = remove)')" "$cur")"
    if [ -z "$users" ]; then
        lsshm_info 'Removing AllowUsers is not handled automatically (edit the managed file).'
        return 0
    fi
    lsshm_apply_dangerous_change "AllowUsers" "$users" "$(lsshm_t 'AllowUsers change')"
}

lsshm_set_allow_groups() {
    local cur; cur="$(lsshm_server_config_effective_value allowgroups)"
    lsshm_info 'Current AllowGroups: %s' "${cur:-$(lsshm_t 'not set')}"
    local groups; groups="$(lsshm_prompt "$(lsshm_t 'Allowed groups (space-separated)')" "$cur")"
    [ -z "$groups" ] && { lsshm_info 'No change.'; return 0; }
    lsshm_apply_dangerous_change "AllowGroups" "$groups" "$(lsshm_t 'AllowGroups change')"
}

# Show the effective configuration (sshd -T) or a helpful message.
lsshm_server_config_show() {
    local dump
    # Explicit request: allow one sudo prompt to get the real effective dump.
    dump="$(lsshm_server_config_dump refresh)" || dump="$(lsshm_server_config_dump)" || dump=""
    if [ -n "$dump" ]; then
        printf '%s\n' "$dump" | sort
    else
        lsshm_warn 'sshd -T unavailable. Detected configuration files:'
        lsshm_config_effective_files
    fi
}
