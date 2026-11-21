#!/usr/bin/env bash
# Software from outside Debian's archive, from each vendor's official source:
#   Google Chrome (Google apt repo), VS Code (Microsoft apt repo), Flathub + Arduino IDE 2,
#   PlatformIO (pipx), Claude Code (Anthropic installer).
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/setup-extras.sh
set -euo pipefail
ARCH=$(dpkg --print-architecture)
sudo apt-get install -y --no-install-recommends gnupg curl ca-certificates
sudo install -d -m 0755 /etc/apt/keyrings

if [[ "$ARCH" == amd64 ]]; then
  echo "== Google Chrome =="
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
else
  echo "!! Google Chrome has no $ARCH build; use Chromium/Firefox instead"
fi

echo "== VS Code =="
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

sudo apt-get update
PKGS=(code)
[[ "$ARCH" == amd64 ]] && PKGS+=(google-chrome-stable)
sudo apt-get install -y "${PKGS[@]}"

echo "== Flathub + Arduino IDE 2 =="
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y --noninteractive flathub cc.arduino.IDE2 || echo "!! Arduino IDE install failed (retry later: flatpak install flathub cc.arduino.IDE2)"

echo "== PlatformIO =="
pipx install platformio || pipx upgrade platformio
pipx ensurepath >/dev/null

echo "== Claude Code =="
if ! command -v claude >/dev/null && [[ ! -x "$HOME/.local/bin/claude" ]]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# serial access for flashing (also done by setup-dev.sh)
sudo usermod -aG dialout "$USER"
echo
echo "OK: extras installed. Versions:"
{ google-chrome-stable --version; code --version | head -1; ~/.local/bin/pio --version; ~/.local/bin/claude --version; } 2>/dev/null || true
