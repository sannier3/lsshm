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
trap 'rm -f "$tmp"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/lsshm.sh" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$REPO_RAW/lsshm.sh"
else
    echo "install.sh: neither curl nor wget is available." >&2
    exit 1
fi

bash -n "$tmp" || { echo "install.sh: downloaded script failed syntax check." >&2; exit 1; }
exec bash "$tmp" install "$@"
