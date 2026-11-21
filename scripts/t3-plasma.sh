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
# startplasma-wayland sets up the rest exactly like the real login (menu prefix, KDE platform
# theme, session manager, autostart -> benchd). Run inside WSLg it opens kwin as a window.
# WSLg's GPU driver crashes kwin: render OpenGL on the CPU (llvmpipe) here; real T3 uses the GPU.
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
echo "T3 (Plasma) starting: settings in $RUN/config"
exec dbus-run-session -- startplasma-wayland
