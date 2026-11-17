#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "GWCU checkout has local changes; commit or resolve them before updating." >&2
    exit 2
fi

git pull --ff-only
exec ./install.sh "$@"
