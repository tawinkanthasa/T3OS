#!/usr/bin/env bash
# Install the T3 desktop (KDE Plasma, Mac-style) + programming + maker packages into WSL Debian.
# Same lists the ISO uses.  Big download (~3-4 GB) the first time.
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/setup-desktop.sh
set -euo pipefail
P="$(dirname "$0")/../os/packages"
list() { grep -v '^\s*#' "$P/$1.list" | tr ' ' '\n' | grep -v '^$'; }
mapfile -t BASE < <(list desktop; list dev)
mapfile -t MAKER < <(list maker)
export DEBIAN_FRONTEND=noninteractive
echo "== T3 desktop: ${#BASE[@]} + ${#MAKER[@]} packages (asks for sudo password) =="
sudo -E apt-get update
sudo -E apt-get install -y "${BASE[@]}"
sudo -E apt-get install -y --no-install-recommends "${MAKER[@]}"
# containers without sudo; serial ports for flashing
sudo usermod -aG dialout,plugdev "$USER"
echo "OK: T3 desktop packages installed"
