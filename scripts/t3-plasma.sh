#!/usr/bin/env bash
# Try the T3 desktop (KDE Plasma) as a window on Windows via WSLg.
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/t3-plasma.sh [--sim]
# Uses a throwaway install tree + fresh settings each run, so ~/.config is left alone.
# The Windows key belongs to Windows here: click inside the T3 window first, then Meta works
# only for keys Windows doesn't grab; the dock and menus work with the mouse.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[[ "${1:-}" == "--sim" ]] && export BENCH_SIM=1
export PATH="$HOME/.venvs/bench/bin:$HOME/.local/bin:$PATH"
pkill -f "venvs/bench/bin/benchd" 2>/dev/null || true

RUN=/tmp/t3-kde && rm -rf "$RUN" && mkdir -p "$RUN/config"
bash "$REPO/os/install.sh" "$RUN/root" >/dev/null
export XDG_DATA_DIRS="$RUN/root/usr/share:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="$RUN/root/etc/xdg:/etc/xdg"
export XDG_CONFIG_HOME="$RUN/config"
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=wayland
cat > "$RUN/start.sh" <<EOS
#!/bin/sh
benchd >"$RUN/benchd.log" 2>&1 &
kded6 >/dev/null 2>&1 &
exec plasmashell
EOS
chmod +x "$RUN/start.sh"
echo "T3 (Plasma) starting: settings in $RUN/config"
exec dbus-run-session -- kwin_wayland --width 1600 --height 900 --no-lockscreen --exec "$RUN/start.sh"
