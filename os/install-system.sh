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
install -m 0644 "$S/apt/80-t3-chrome" /etc/apt/apt.conf.d/80-t3-chrome
/usr/share/t3/bin/t3-chrome-fix || true
install -m 0644 "$S/grub/t3.cfg" /etc/default/grub.d/t3.cfg
install -m 0644 "$S/default/zramswap" /etc/default/zramswap
install -m 0644 "$S/systemd/grub-btrfsd.conf" /etc/systemd/system/grub-btrfsd.service.d/t3.conf
install -m 0644 "$S/systemd/t3-snapshot.service" "$S/systemd/t3-snapshot.timer" "$S/systemd/t3-boot-refresh.service" /etc/systemd/system/
install -m 0644 "$S"/systemd-user/* /usr/lib/systemd/user/
install -m 0644 "$S/profile.d/t3.sh" /etc/profile.d/t3.sh
install -D -m 0644 "$S/polkit/org.t3.windows-next.policy" /usr/share/polkit-1/actions/org.t3.windows-next.policy
install -D -m 0644 "$S/polkit/org.t3.boot.policy" /usr/share/polkit-1/actions/org.t3.boot.policy
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
en t3-boot-refresh.service
[[ -x /usr/bin/grub-btrfsd && "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]] && en grub-btrfsd.service
systemctl --global enable t3-update-check.timer >/dev/null 2>&1 || true

# ---- faster start: switch off what a desktop PC without these things doesn't need (same look, same apps)
# waiting for the internet held the boot ~6 s; apps that need the net wait for it themselves
systemctl disable NetworkManager-wait-online.service >/dev/null 2>&1 || true
# phone-modem service: started on every boot even with no modem (turn back on: sudo systemctl enable --now ModemManager)
command -v mmcli >/dev/null && ! mmcli -L 2>/dev/null | grep -q /Modem/ && systemctl disable ModemManager.service >/dev/null 2>&1 || true
# ext4 snapshot cleanup: T3 is on Btrfs, nothing to clean
[[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]] && systemctl mask e2scrub_reap.service >/dev/null 2>&1 || true
# drivers for printers on the old 25-pin parallel port (cups loads them on every boot); USB/network
# printers don't use them
if [[ -f /etc/modules-load.d/cups-filters.conf ]] && ! grep -q '^# T3' /etc/modules-load.d/cups-filters.conf; then
  sed -i 's/^\(lp\|ppdev\|parport_pc\)$/# \1/; 1i # T3: parallel-port printer drivers off (USB/network printers are unaffected)' /etc/modules-load.d/cups-filters.conf
fi

# ---- Windows on the same PC keeps the hardware clock in local time; T3 does the same, otherwise
# Windows shows the wrong time (7 h off in Thailand) after every T3 session
if command -v efibootmgr >/dev/null && efibootmgr 2>/dev/null | grep -qi 'windows boot manager'; then
  timedatectl set-local-rtc 1 >/dev/null 2>&1 || true
fi

# ---- Timeshift on a Btrfs root (an ISO chroot isn't one; the installer does this step there)
if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs && ! -s /etc/timeshift/timeshift.json ]]; then
  install -d /etc/timeshift
  sed "s/@UUID@/$(findmnt -no UUID /)/" "$S/t3/timeshift.json.in" > /etc/timeshift/timeshift.json
fi

# ---- T3 look while booting: themed boot menu + Plymouth splash (chip logo)
if command -v rsvg-convert >/dev/null && command -v grub-mkfont >/dev/null; then
  rm -rf /boot/grub/themes/t3
  bash "$REPO/os/boot/render.sh" grub /boot/grub/themes/t3 installed >/dev/null || echo "  (ธีมเมนูบูตไม่สำเร็จ ข้าม)"
  if command -v plymouth-set-default-theme >/dev/null; then
    rm -rf /usr/share/plymouth/themes/t3
    bash "$REPO/os/boot/render.sh" plymouth /usr/share/plymouth/themes/t3 >/dev/null
    plymouth-set-default-theme t3 && update-initramfs -u >/dev/null 2>&1 || echo "  (ตั้ง Plymouth ไม่สำเร็จ ข้าม)"
  fi
fi
# "About this system" says T3 (KDE also reads /etc/xdg/kcm-about-distrorc)
[[ -f /usr/lib/os-release ]] && sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="T3 (Debian 13)"/' /usr/lib/os-release

# ---- the boot menu picks up the T3 name, Windows, snapshots
GB=/etc/default/grub-btrfs/config   # snapshot submenu says "T3", not "Debian GNU/Linux"
if [[ -f "$GB" ]]; then
  sed -i '/^#\?GRUB_BTRFS_SUBMENUNAME=/d' "$GB"
  echo 'GRUB_BTRFS_SUBMENUNAME="T3 restore points (snapshots)"' >> "$GB"
fi
# a copy of the boot loader at EFI/BOOT/BOOTX64.EFI: an external disk then boots on any PC (F12)
if [[ -d /sys/firmware/efi ]] && mountpoint -q /boot/efi && command -v grub-install >/dev/null; then
  grub-install --removable --efi-directory=/boot/efi --no-nvram >/dev/null 2>&1 || echo "  (EFI fallback ไม่สำเร็จ ข้าม)"
fi
# update-grub also tidies the menu (t3-grub-names): Debian's own is kept as update-grub.debian
if [[ -x /usr/sbin/update-grub ]] && ! dpkg-divert --list /usr/sbin/update-grub | grep -q update-grub.debian; then
  dpkg-divert --local --rename --divert /usr/sbin/update-grub.debian --add /usr/sbin/update-grub >/dev/null
fi
[[ -x /usr/sbin/update-grub.debian ]] && install -m 0755 "$S/grub/update-grub" /usr/sbin/update-grub
if command -v update-grub >/dev/null && [[ -e /boot/grub/grub.cfg ]]; then
  update-grub >/dev/null 2>&1 || echo "  (update-grub ไม่สำเร็จ: ลองรันเองภายหลัง)"
fi
udevadm control --reload >/dev/null 2>&1 || true
echo "T3 system setup done"
