#!/usr/bin/env bash
# One-time setup of the T3 build environment inside WSL Debian.
# Run:  wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/setup-dev.sh
set -euo pipefail

echo "== T3 dev setup: will ask for your Debian (sudo) password once =="
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  git curl ca-certificates \
  python3 python3-venv python3-pip \
  live-build debootstrap squashfs-tools xorriso mtools dosfstools \
  grub-efi-amd64-bin grub-pc-bin \
  sway swaybg foot fonts-jetbrains-mono fonts-noto-core fonts-thai-tlwg \
  usbutils

# serial ports without sudo
sudo usermod -aG dialout "$USER"

# bench venv on the Linux side (shared source, separate venv)
REPO=/mnt/c/Users/tawin/T3OS
python3 -m venv "$HOME/.venvs/bench"
"$HOME/.venvs/bench/bin/pip" install -q --upgrade pip
"$HOME/.venvs/bench/bin/pip" install -q -e "$REPO/bench" pytest
cd "$REPO/bench" && BENCH_SIM=1 "$HOME/.venvs/bench/bin/python" -m pytest -q tests -p no:cacheprovider

echo
echo "== done. versions =="
lb --version | head -1 || true
sway --version || true
python3 --version
echo "OK: T3 dev environment ready"
