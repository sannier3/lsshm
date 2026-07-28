# shellcheck shell=bash
# =============================================================================
# updater.sh - configuration file and safe self-update
# =============================================================================

# --- configuration file (INI-style key=value) --------------------------------

lsshm_config_default() {
    cat <<EOF
# LSSHM configuration
update_check=daily
update_channel=stable
EOF
}

lsshm_config_load() {
    LSSHM_CFG_UPDATE_CHECK="daily"
    LSSHM_CFG_UPDATE_CHANNEL="stable"
    LSSHM_CFG_LANG=""
    [ -r "$LSSHM_CONFIG_FILE" ] || return 0
    local line key val
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"; val="${line#*=}"
        key="$(printf '%s' "$key" | tr -d '[:space:]')"
        val="$(printf '%s' "$val" | tr -d '[:space:]')"
        case "$key" in
            update_check)   LSSHM_CFG_UPDATE_CHECK="$val" ;;
            update_channel) LSSHM_CFG_UPDATE_CHANNEL="$val" ;;
            language)       LSSHM_CFG_LANG="$val" ;;
        esac
    done <"$LSSHM_CONFIG_FILE"
}

lsshm_config_write_default() {
    lsshm_ensure_dirs
    [ -f "$LSSHM_CONFIG_FILE" ] && return 0
    lsshm_config_default >"$LSSHM_CONFIG_FILE"
}

lsshm_config_set() {
    local key="$1" value="$2"
    lsshm_ensure_dirs
    [ -f "$LSSHM_CONFIG_FILE" ] || lsshm_config_default >"$LSSHM_CONFIG_FILE"
    local tmp; tmp="$(lsshm_mktemp)"
    if grep -q "^${key}=" "$LSSHM_CONFIG_FILE" 2>/dev/null; then
        sed "s|^${key}=.*|${key}=${value}|" "$LSSHM_CONFIG_FILE" >"$tmp"
    else
        cat "$LSSHM_CONFIG_FILE" >"$tmp"
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
    fi
    install -m 0644 "$tmp" "$LSSHM_CONFIG_FILE"
}

# --- download helpers --------------------------------------------------------

lsshm_download() {
    # lsshm_download URL OUTFILE
    local url="$1" out="$2"
    if lsshm_have curl; then
        curl -fsSL "$url" -o "$out"
    elif lsshm_have wget; then
        wget -qO "$out" "$url"
    else
        lsshm_error 'Neither curl nor wget available for download.'
        return 1
    fi
}

lsshm_remote_version() {
    local tmp; tmp="$(lsshm_mktemp)"
    if lsshm_download "$LSSHM_REPO_RAW/VERSION" "$tmp" 2>/dev/null; then
        tr -d '[:space:]' <"$tmp"
    fi
}

lsshm_version_gt() {
    # returns 0 if $1 > $2 (semantic-ish numeric compare)
    [ "$1" = "$2" ] && return 1
    local greater
    greater="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)"
    [ "$greater" = "$1" ]
}

# --- update check ------------------------------------------------------------

lsshm_update_stamp() { printf '%s/last_update_check' "$LSSHM_CACHE_DIR"; }

lsshm_update_should_check() {
    lsshm_config_load
    case "$LSSHM_CFG_UPDATE_CHECK" in
        never) return 1 ;;
        always) return 0 ;;
        daily|*)
            local stamp; stamp="$(lsshm_update_stamp)"
            [ -f "$stamp" ] || return 0
            local last now
            last="$(cat "$stamp" 2>/dev/null || echo 0)"
            now="$(date +%s)"
            [ $((now - last)) -ge 86400 ]
            ;;
    esac
}

lsshm_update_touch_stamp() {
    lsshm_ensure_dirs
    date +%s >"$(lsshm_update_stamp)" 2>/dev/null || true
}

# Light check performed at startup.
lsshm_update_check() {
    lsshm_update_should_check || return 0
    lsshm_update_touch_stamp
    local remote; remote="$(lsshm_remote_version)"
    [ -n "$remote" ] || return 0
    if lsshm_version_gt "$remote" "$LSSHM_VERSION"; then
        printf '\n'
        lsshm_out 'Installed version: %s' "$LSSHM_VERSION"
        lsshm_out 'Available version: %s' "$remote"
        printf '\n'
        lsshm_out 'An update is available.'
        if lsshm_confirm "$(lsshm_t 'Install now?')" no; then
            lsshm_update_run
        fi
    fi
}

# --- safe update -------------------------------------------------------------

lsshm_update_run() {
    lsshm_ensure_dirs
    local target="$LSSHM_INSTALL_TARGET"
    if [ ! -f "$target" ]; then
        lsshm_warn 'LSSHM does not seem to be installed in %s.' "$target"
        lsshm_info 'Use: curl -fsSL %s/lsshm.sh | bash -s -- install' "$LSSHM_REPO_RAW"
        return 1
    fi

    local remote; remote="$(lsshm_remote_version)"
    lsshm_info 'Installed version: %s' "$LSSHM_VERSION"
    lsshm_info 'Remote version : %s' "${remote:-$(lsshm_t 'unknown')}"

    # 1. Download to a temporary file.
    local tmp; tmp="$(lsshm_mktemp)"
    lsshm_info 'Downloading the new version...'
    if ! lsshm_download "$LSSHM_REPO_RAW/lsshm.sh" "$tmp"; then
        lsshm_error 'Download failed.'
        return 1
    fi

    # 2. Validate syntax with bash -n.
    if ! bash -n "$tmp"; then
        lsshm_error 'The downloaded script has syntax errors. Aborting.'
        return 1
    fi

    # 3. Verify SHA-256 against the published SHA256SUMS.
    if ! lsshm_update_verify_checksum "$tmp"; then
        lsshm_error 'SHA-256 verification failed. Aborting.'
        return 1
    fi

    # 4. Sanity check: the new file must identify itself as LSSHM.
    if ! grep -q "LSSHM" "$tmp"; then
        lsshm_error 'The downloaded file does not look like LSSHM. Aborting.'
        return 1
    fi

    # 5/6. Keep previous version, then replace atomically.
    cp -a "$target" "$target.prev" 2>/dev/null || true
    chmod +x "$tmp"
    if install -m 0755 "$tmp" "$target"; then
        lsshm_ok 'Update installed. Previous version kept: %s' "$target.prev"
        lsshm_info "Use 'lsshm update rollback' to revert."
    else
        lsshm_error 'File replacement failed.'
        return 1
    fi
}

# Fail-closed: any missing tool, missing file, or mismatch aborts the caller.
lsshm_update_verify_checksum() {
    local file="$1"
    if [ ! -f "$file" ]; then
        lsshm_error 'File to verify not found.'
        return 1
    fi
    local sums; sums="$(lsshm_mktemp)"
    if ! lsshm_download "$LSSHM_REPO_RAW/SHA256SUMS" "$sums" 2>/dev/null; then
        lsshm_error 'SHA256SUMS unavailable: cannot verify (aborting).'
        return 1
    fi
    local expected actual
    # Accept both text ("hash  lsshm.sh") and binary ("hash *lsshm.sh") formats.
    expected="$(awk '
        {
            f = $2
            sub(/^\*/, "", f)
            if (f == "lsshm.sh") { print $1; exit }
        }
    ' "$sums")"
    if [ -z "$expected" ]; then
        lsshm_error 'lsshm.sh checksum missing from SHA256SUMS (aborting).'
        return 1
    fi
    if lsshm_have sha256sum; then
        actual="$(sha256sum "$file" | awk '{print $1}')"
    elif lsshm_have shasum; then
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    else
        lsshm_error 'No SHA-256 tool (sha256sum/shasum): cannot verify (aborting).'
        return 1
    fi
    if [ "$expected" != "$actual" ]; then
        lsshm_error 'Incorrect SHA-256 checksum.'
        lsshm_error '  expected: %s' "$expected"
        lsshm_error '  actual:   %s' "$actual"
        return 1
    fi
    lsshm_ok 'SHA-256 checksum verified.'
    return 0
}

lsshm_update_rollback() {
    local target="$LSSHM_INSTALL_TARGET"
    if [ ! -f "$target.prev" ]; then
        lsshm_error 'No previous version available (%s).' "$target.prev"
        return 1
    fi
    lsshm_confirm "$(lsshm_t 'Restore the previous version of LSSHM?')" no || { lsshm_info 'Cancelled.'; return 0; }
    if install -m 0755 "$target.prev" "$target"; then
        lsshm_ok 'Previous version restored.'
    else
        lsshm_error 'Restore failed.'
        return 1
    fi
}
