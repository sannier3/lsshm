#!/usr/bin/env bash
# =============================================================================
# install.sh - convenience bootstrap for LSSHM
# =============================================================================
# This downloads the single-file lsshm.sh and runs its "install" command.
# You can also install directly with:
#   curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
set -euo pipefail

REPO_RAW="${LSSHM_REPO_RAW:-https://raw.githubusercontent.com/sannier3/lsshm/main}"

# If run from a checkout that already contains lsshm.sh, use it directly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lsshm.sh" ]; then
    exec bash "$SCRIPT_DIR/lsshm.sh" install "$@"
fi

tmp="$(mktemp)"
sums="$(mktemp)"
trap 'rm -f "$tmp" "$sums"' EXIT

download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        echo "install.sh: neither curl nor wget is available." >&2
        exit 1
    fi
}

download "$REPO_RAW/lsshm.sh" "$tmp"
bash -n "$tmp" || { echo "install.sh: downloaded script failed syntax check." >&2; exit 1; }

# Fail-closed SHA-256 verification before executing the downloaded script.
download "$REPO_RAW/SHA256SUMS" "$sums" || {
    echo "install.sh: SHA256SUMS unavailable; refusing to continue." >&2
    exit 1
}
# Accept both text ("hash  lsshm.sh") and binary ("hash *lsshm.sh") formats.
expected="$(awk '{ f=$2; sub(/^\*/,"",f); if (f=="lsshm.sh") { print $1; exit } }' "$sums")"
[ -n "$expected" ] || { echo "install.sh: lsshm.sh hash missing from SHA256SUMS." >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
else
    echo "install.sh: no SHA-256 tool available; refusing to continue." >&2
    exit 1
fi
if [ "$expected" != "$actual" ]; then
    echo "install.sh: SHA-256 mismatch." >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi

exec bash "$tmp" install "$@"
