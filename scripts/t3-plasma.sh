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
for n in kwin_wayland_wrapper kwin_wayland plasmashell kactivitymanagerd kded6; do pkill -f "/$n( |$)" 2>/dev/null || pkill -x "$n" 2>/dev/null || true; done

RUN=/tmp/t3-kde && rm -rf "$RUN" && mkdir -p "$RUN/config"
bash "$REPO/os/install.sh" "$RUN/root" >/dev/null
export XDG_DATA_DIRS="$RUN/root/usr/share:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="$RUN/root/etc/xdg:/etc/xdg"
export XDG_CONFIG_HOME="$RUN/config"
# What startplasma does on the real login: KDE menus (otherwise no app resolves and nothing
# opens from the dock), the KDE Qt theme (icons), session type.
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
export XDG_MENU_PREFIX=plasma- QT_QPA_PLATFORMTHEME=kde XDG_SESSION_TYPE=wayland
# WSLg: kwin as a *Wayland* window never shows frames (window stays white / "not responding"),
# and its GPU path crashes. So kwin runs as an X11 window on WSLg's X server, drawing with
# QPainter. Real T3 runs kwin on the hardware with the GPU. (startplasma-wayland can't be used
# either: under WSLg its shell lands on WSLg's display instead of inside kwin.)
export KWIN_COMPOSE=Q
HOST_WL="${WAYLAND_DISPLAY:-}"; unset WAYLAND_DISPLAY
cat > "$RUN/start.sh" <<EOS
#!/bin/sh
export QT_QPA_PLATFORM=wayland
# runs inside kwin, so everything below gets kwin's display
dbus-update-activation-environment --all
kbuildsycoca6 >/dev/null 2>&1
/usr/libexec/kactivitymanagerd >/dev/null 2>&1 &
kded6 >/dev/null 2>&1 &
benchd >"$RUN/benchd.log" 2>&1 &
exec plasmashell
EOS
chmod +x "$RUN/start.sh"
echo "T3 (Plasma) starting: settings in $RUN/config"
exec dbus-run-session -- kwin_wayland --x11-display "${DISPLAY:-:0}" --width 1600 --height 900 --no-lockscreen "$RUN/start.sh"
