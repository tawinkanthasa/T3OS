#!/usr/bin/env bash
# Start (or restart) benchd inside WSL for UI development.
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/scripts/t3-dev.sh [--sim]
# Then open http://localhost:7300 in a Windows browser.
set -euo pipefail
if [[ "${1:-}" == "--sim" ]]; then export BENCH_SIM=1; fi
pid=$(pgrep -f "venvs/bench/bin/python.*benchd|venvs/bench/bin/benchd" || true)
[[ -n "$pid" ]] && kill $pid && sleep 0.5
cd "$HOME"
nohup "$HOME/.venvs/bench/bin/benchd" > /tmp/benchd.log 2>&1 &
sleep 1.5
cat /tmp/benchd.log
echo "open http://localhost:7300"
