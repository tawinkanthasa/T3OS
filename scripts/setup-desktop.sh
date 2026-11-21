#!/usr/bin/env bash
# Install the T3 desktop packages into WSL Debian (same list the ISO uses).
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/setup-desktop.sh
set -euo pipefail
LIST="$(dirname "$0")/../os/packages/desktop.list"
mapfile -t PKGS < <(grep -v '^\s*#' "$LIST" | tr ' ' '\n' | grep -v '^$')
echo "== T3 desktop: ${#PKGS[@]} packages (asks for sudo password) =="
sudo apt-get update
sudo apt-get install -y "${PKGS[@]}"
echo "OK: T3 desktop packages installed"
