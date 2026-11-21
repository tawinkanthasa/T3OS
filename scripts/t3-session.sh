#!/usr/bin/env bash
# Run the full T3 desktop (Sway session) as a window on Windows via WSLg.
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/t3-session.sh [--sim]
# Inside the window the Windows key belongs to Windows, so $mod = Alt here (Super on real T3).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[[ "${1:-}" == "--sim" ]] && export BENCH_SIM=1
export PATH="$HOME/.venvs/bench/bin:$HOME/.local/bin:$PATH"   # benchd, bench, pio, claude

pkill -f "venvs/bench/bin/benchd" 2>/dev/null || true

RUN=/tmp/t3-dev && rm -rf "$RUN" && mkdir -p "$RUN"
cp -r "$REPO/os/." "$RUN/" && chmod +x "$RUN"/bin/*
# point configs and scripts at this copy instead of /usr/share/t3
grep -rl /usr/share/t3 "$RUN" | xargs -r sed -i "s#/usr/share/t3#$RUN#g"
sed -i "s#^set \$t3 .*#set \$t3 $RUN#; s#^set \$mod .*#set \$mod Mod1#" "$RUN/sway/config"
# WSL-only: WSLg owns /tmp/.X11-unix (no Xwayland); no NetworkManager/gamma control in a nested window
sed -i "/^exec nm-applet/d; /^exec gammastep/d" "$RUN/sway/config"
echo "xwayland disable" >> "$RUN/sway/config"

# same session environment as the real login (os/bin/t3-start)
export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
export MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=gtk3
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx ELECTRON_OZONE_PLATFORM_HINT=auto
export T3_FUZZEL="$RUN/fuzzel/fuzzel.ini"
export WLR_BACKENDS=wayland WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1
echo "T3 session starting (configs: $RUN). mod key = Alt"
# WSL has no per-user D-Bus; give the session its own so mako/notify-send/gsettings work
exec dbus-run-session -- sway -c "$RUN/sway/config" 2> >(grep -v "sticky bit" >&2)
