#!/usr/bin/env bash
# Report lsshm_* tokens that are called but never defined (catches typos).
set -eu
file="${1:-lsshm.sh}"
defined="$(grep -oE '^[[:space:]]*lsshm_[a-zA-Z0-9_]+\(\)' "$file" | tr -d ' ()' | sort -u)"
used="$(grep -oE 'lsshm_[a-zA-Z0-9_]+' "$file" | sort -u)"
missing=0
while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
        LSSHM_*|lsshm_[A-Z]*) continue ;;
    esac
    if ! printf '%s\n' "$defined" | grep -qx "$name"; then
        printf 'UNDEFINED: %s\n' "$name"
        missing=1
    fi
done <<EOF
$used
EOF
[ "$missing" = "0" ] && echo "integrity OK: all lsshm_* calls resolve"
