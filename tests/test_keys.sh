# shellcheck shell=bash
# Tests for version comparison and key fingerprint parsing.

assert_true  "lsshm_version_gt 0.2.0 0.1.0" "0.2.0 > 0.1.0"
assert_true  "lsshm_version_gt 0.1.10 0.1.9" "0.1.10 > 0.1.9"
assert_true  "lsshm_version_gt 1.0.0 0.9.9" "1.0.0 > 0.9.9"
assert_false "lsshm_version_gt 0.1.0 0.1.0" "equal versions are not greater"
assert_false "lsshm_version_gt 0.1.0 0.2.0" "0.1.0 is not > 0.2.0"

# Fingerprint parsing requires ssh-keygen; skip gracefully if absent.
if command -v ssh-keygen >/dev/null 2>&1; then
    _tmpdir="$(mktemp -d)"
    ssh-keygen -t ed25519 -N "" -C "test@lsshm" -f "$_tmpdir/id_ed25519" >/dev/null 2>&1
    _line="$(cat "$_tmpdir/id_ed25519.pub")"
    _fp="$(lsshm_access_fingerprint_line "$_line")"
    assert_true "printf '%s' \"$_fp\" | grep -q 'SHA256:'" "fingerprint contains SHA256"
    assert_true "printf '%s' \"$_fp\" | grep -qi 'ED25519'" "fingerprint reports ED25519"
    rm -rf "$_tmpdir"
else
    printf '  skip ssh-keygen not available\n'
fi
