# shellcheck shell=bash
# Tests for authorized_keys indexing consistency and checksum fail-closed.

# --- unified indexing (list / remove / disable) ------------------------------

_save_user_home="$(declare -f lsshm_user_home)"
_save_access_file="$(declare -f lsshm_access_file)"
_save_access_read="$(declare -f lsshm_access_read)"
_save_backup_ak="$(declare -f lsshm_backup_authorized_keys)"
_save_access_write="$(declare -f lsshm_access_write)"
_save_fp="$(declare -f lsshm_access_fingerprint_line)"

_tmpdir="$(mktemp -d)"
_ak="$_tmpdir/.ssh/authorized_keys"
mkdir -p "$_tmpdir/.ssh"
cat >"$_ak" <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA active-one
# LSSHM-DISABLED ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB disabled-two
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC active-three
EOF

lsshm_user_home() { printf '%s' "$_tmpdir"; }
lsshm_access_file() { printf '%s' "$_ak"; }
lsshm_access_read() { cat "$1"; }
lsshm_backup_authorized_keys() { return 0; }
lsshm_access_write() { local _u="$1" _f="$2" _t="$3"; install -m 0600 "$_t" "$_f"; }
# Index matching must work even when fingerprints are stubbed.
lsshm_access_fingerprint_line() {
    printf '256 SHA256:fixture-%s (ED25519)' "$(printf '%s' "$1" | awk '{print $NF}')"
}

# Index 2 must be the disabled entry; removing it should leave two managed lines.
lsshm_access_remove "fixture" "2"
_remaining="$(grep -cE '^(ssh-|# LSSHM-DISABLED )' "$_ak" || true)"
assert_eq "2" "$_remaining" "remove index 2 drops disabled entry only"
assert_true "grep -q 'active-one$' \"$_ak\"" "first active key kept after remove 2"
assert_true "grep -q 'active-three$' \"$_ak\"" "third active key kept after remove 2"
assert_false "grep -q 'disabled-two' \"$_ak\"" "disabled entry removed by index 2"

# Rebuild fixture and disable index 1 (first active).
cat >"$_ak" <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA active-one
# LSSHM-DISABLED ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB disabled-two
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC active-three
EOF
lsshm_access_disable "fixture" "1"
assert_true "grep -q '^# LSSHM-DISABLED .*active-one' \"$_ak\"" "disable index 1 targets first active key"
assert_true "grep -q '^# LSSHM-DISABLED .*disabled-two' \"$_ak\"" "previous disabled entry still present"
assert_true "grep -q '^ssh-ed25519 .*active-three$' \"$_ak\"" "third key remains active"

# Re-enable index 1 (now the disabled active-one).
lsshm_access_disable "fixture" "1"
assert_true "grep -q '^ssh-ed25519 .*active-one$' \"$_ak\"" "disable index 1 re-enables first entry"

rm -rf "$_tmpdir"
eval "$_save_user_home"
eval "$_save_access_file"
eval "$_save_access_read"
eval "$_save_backup_ak"
eval "$_save_access_write"
eval "$_save_fp"

# --- checksum fail-closed ----------------------------------------------------

_save_download="$(declare -f lsshm_download)"

assert_false "lsshm_update_verify_checksum /nonexistent/lsshm.sh 2>/dev/null" \
    "checksum verify fails on missing file"

lsshm_download() { return 1; }
_tmpf="$(mktemp)"
printf '#!/bin/bash\necho LSSHM\n' >"$_tmpf"
assert_false "lsshm_update_verify_checksum \"$_tmpf\" 2>/dev/null" \
    "checksum verify fails when SHA256SUMS unavailable"
rm -f "$_tmpf"
eval "$_save_download"
