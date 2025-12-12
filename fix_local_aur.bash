#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/var/lib/repo/aur"
DB_ARCHIVE="aur.db.tar.gz"
DB_LINK="aur.db"

if [[ ! -d "$REPO_DIR" ]]; then
    echo "Repo directory not found: $REPO_DIR" >&2
    exit 0
fi

cd "$REPO_DIR"

shopt -s nullglob
pkgs=(*.pkg.*)

# If there are no packages, there's nothing meaningful to index.
# Pacman will still fail to refresh a file:// repo with no DB,
# but without at least one package, we cannot create a valid DB.
if [[ ${#pkgs[@]} -eq 0 ]]; then
    exit 0
fi

# Only (re)create the DB if it is missing. This keeps the script fast and idempotent.
if [[ ! -e "$DB_LINK" || ! -e "$DB_ARCHIVE" ]]; then
    repo-add -n -R -p "$DB_ARCHIVE" "${pkgs[@]}"
fi

exit 0
