#!/usr/bin/env bash
# System side of T3 for a real install (ISO chroot, or an existing Debian 13 machine):
# boot menu, snapshots, zram, auto security updates, T3 Bench service, update checker.
#   sudo os/install-system.sh            install (ISO build hook / existing machine)
#   sudo os/install-system.sh --update   same, from `t3-get t3`
# Run os/install.sh first (desktop files). Safe to re-run. Not for WSL.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$SRC")"; S="$SRC/system"
[[ $EUID -eq 0 ]] || { echo "ต้องรันด้วย sudo"; exit 1; }
# --update (from `t3-get t3`) runs the same steps; everything below keeps local settings

install -d /etc/default/grub.d /etc/systemd/system/grub-btrfsd.service.d /etc/t3 /usr/lib/systemd/user
install -m 0644 "$S/apt/80-t3-snapshot" /etc/apt/apt.conf.d/80-t3-snapshot
install -m 0644 "$S/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
install -m 0644 "$S/grub/t3.cfg" /etc/default/grub.d/t3.cfg
install -m 0644 "$S/default/zramswap" /etc/default/zramswap
install -m 0644 "$S/systemd/grub-btrfsd.conf" /etc/systemd/system/grub-btrfsd.service.d/t3.conf
install -m 0644 "$S/systemd/t3-snapshot.service" "$S/systemd/t3-snapshot.timer" /etc/systemd/system/
install -m 0644 "$S"/systemd-user/* /usr/lib/systemd/user/
install -m 0644 "$S/profile.d/t3.sh" /etc/profile.d/t3.sh
install -m 0644 "$S/t3/timeshift.json.in" /usr/share/t3/timeshift.json.in
# keep a repo URL the user already set
[[ -f /etc/t3/update.conf ]] && grep -q '^repo=.\+' /etc/t3/update.conf || install -m 0644 "$S/t3/update.conf" /etc/t3/update.conf

# ---- T3 Bench as a system-wide app (its own venv; benchd/bench/bench-mcp on PATH)
VENV=/opt/t3/bench
[[ -x "$VENV/bin/python" ]] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q --upgrade "$REPO/bench"
for b in bench benchd bench-mcp; do ln -sf "$VENV/bin/$b" "/usr/local/bin/$b"; done

# ---- services
systemctl daemon-reload 2>/dev/null || true
en() { systemctl enable "$@" >/dev/null 2>&1 || echo "  (เปิด $* ไม่ได้ ข้าม)"; }
en zramswap.service
en systemd-oomd.service
en unattended-upgrades.service
en t3-snapshot.timer
[[ -x /usr/bin/grub-btrfsd && "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]] && en grub-btrfsd.service
systemctl --global enable t3-update-check.timer >/dev/null 2>&1 || true

# ---- Timeshift on a Btrfs root (an ISO chroot isn't one; the installer does this step there)
if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs && ! -s /etc/timeshift/timeshift.json ]]; then
  install -d /etc/timeshift
  sed "s/@UUID@/$(findmnt -no UUID /)/" "$S/t3/timeshift.json.in" > /etc/timeshift/timeshift.json
fi

# ---- the boot menu picks up the T3 name, Windows, snapshots
if command -v update-grub >/dev/null && [[ -e /boot/grub/grub.cfg ]]; then
  update-grub >/dev/null 2>&1 || echo "  (update-grub ไม่สำเร็จ: ลองรันเองภายหลัง)"
fi
udevadm control --reload >/dev/null 2>&1 || true
echo "T3 system setup done"
