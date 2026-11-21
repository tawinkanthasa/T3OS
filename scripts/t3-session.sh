#!/usr/bin/env bash
# Run the full T3 desktop (Sway session) as a window on Windows via WSLg.
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/t3-session.sh [--sim]
# Close the window (or Super+Shift+E) to quit. Inside a nested window the "Super" key
# may be grabbed by Windows; use Alt instead: this script maps $mod to Alt.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[[ "${1:-}" == "--sim" ]] && export BENCH_SIM=1
export PATH="$HOME/.venvs/bench/bin:$PATH"   # benchd, bench, bench-mcp

# benchd: reuse if running, otherwise the session starts it
pkill -f "venvs/bench/bin/benchd" 2>/dev/null || true

RUN=/tmp/t3-dev && rm -rf "$RUN" && mkdir -p "$RUN"
cp -r "$REPO/os/." "$RUN/"
# point configs at this checkout instead of /usr/share/t3
grep -rl /usr/share/t3 "$RUN" | xargs sed -i "s#/usr/share/t3#$RUN#g"
sed -i "s#^set \$t3 .*#set \$t3 $RUN#; s#^set \$mod .*#set \$mod Mod1#" "$RUN/sway/config"
# WSL-only tweaks: WSLg owns /tmp/.X11-unix (no Xwayland) and there is no NetworkManager
sed -i "/^exec nm-applet/d" "$RUN/sway/config"
echo "xwayland disable" >> "$RUN/sway/config"

export WLR_BACKENDS=wayland      # nested inside WSLg's compositor
export WLR_RENDERER=pixman       # WSLg has no GPU path for wlroots
export WLR_NO_HARDWARE_CURSORS=1
export XDG_CURRENT_DESKTOP=sway
echo "T3 session starting (configs: $RUN). mod key = Alt"
# WSL has no per-user D-Bus; give the session its own so mako/notify-send work
exec dbus-run-session -- sway -c "$RUN/sway/config" 2> >(grep -v "sticky bit" >&2)
