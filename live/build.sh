#!/usr/bin/env bash
# Build the T3 ISO with Debian live-build (in WSL Debian or any Debian 13 machine).
#   wsl -d Debian -- bash /mnt/c/Users/tawin/T3OS/live/build.sh
# Asks for your sudo password. Needs ~25 GB free and a good connection; takes 30-90 minutes.
# Output: build/t3-<date>-amd64.iso in the repo.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${T3_LIVE_WORK:-$HOME/t3-live}"      # must be on the Linux filesystem, not /mnt/c
OUT="$REPO/build"
list() { grep -v '^\s*#' "$REPO/os/packages/$1.list" | tr ' ' '\n' | grep -v '^$'; }

command -v lb >/dev/null || sudo apt-get install -y live-build
sudo apt-get install -y --no-install-recommends debootstrap squashfs-tools xorriso mtools dosfstools \
  grub-efi-amd64-bin grub-pc-bin shim-signed grub-efi-amd64-signed >/dev/null

if [[ -d "$WORK" ]]; then (cd "$WORK" && sudo lb clean --purge >/dev/null 2>&1 || true); sudo rm -rf "$WORK"; fi
mkdir -p "$WORK" "$OUT"; cd "$WORK"

BOOT="boot=live components quiet"
BOOT+=" locales=th_TH.UTF-8 keyboard-layouts=us,th keyboard-options=grp:alt_shift_toggle timezone=Asia/Bangkok"
BOOT+=" username=t3 user-fullname=T3 hostname=t3"
BOOT+=" user-default-groups=audio,cdrom,dip,floppy,video,plugdev,netdev,powerdev,scanner,bluetooth,dialout,adm,sudo"

lb config \
  --distribution trixie \
  --architectures amd64 --linux-flavours amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --mirror-bootstrap http://deb.debian.org/debian/ --mirror-chroot http://deb.debian.org/debian/ \
  --mirror-binary http://deb.debian.org/debian/ \
  --security true --updates true \
  --debian-installer none \
  --binary-images iso-hybrid \
  --uefi-secure-boot enable \
  --firmware-binary true --firmware-chroot true \
  --apt-recommends true \
  --memtest none \
  --iso-application "T3" --iso-publisher "T3" --iso-volume "T3" \
  --image-name t3 \
  --checksums sha256 \
  --bootappend-live "$BOOT" >/dev/null

# ---- packages (maker tools go in a hook without recommends: KiCad's 3D models alone are ~5 GB)
{ list desktop; list dev; list safety; list firmware; list live; } | sort -u > config/package-lists/t3.list.chroot

# ---- T3 sources inside the image (hooks install from here; `t3-get t3` updates replace it)
SRC=config/includes.chroot/usr/src/t3
mkdir -p "$SRC"
tar -C "$REPO" --exclude=.git --exclude='*.venv' --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache \
    --exclude=.impeccable --exclude=build --exclude=live/cache -cf - bench os ui scripts | tar -C "$SRC" -xf -
git -C "$REPO" rev-parse --short=12 HEAD > "$SRC/COMMIT" 2>/dev/null || echo unknown > "$SRC/COMMIT"
list maker > "$SRC/maker.list"
# updates: point installed systems at this repo's GitHub copy (git remote "origin")
ORIGIN=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
if [[ "$ORIGIN" == https://* ]]; then
  sed -i "s#^repo=.*#repo=$ORIGIN#" "$SRC/os/system/t3/update.conf"
  echo "updates from: $ORIGIN"
else
  echo "!! no https git remote 'origin': installed systems won't find updates (set repo= in /etc/t3/update.conf)"
fi

# ---- hooks (run inside the image, in name order)
# (lb config already put symlinks to its own root-owned hooks there: touch only ours)
for h in "$REPO"/live/hooks/*.hook.chroot; do install -m 0755 "$h" config/hooks/normal/; done

echo "== building T3 ISO in $WORK (log: $WORK/build.log) =="
sudo lb build 2>&1 | tee build.log
ISO=$(ls -1 "$WORK"/t3-*.iso 2>/dev/null | head -1)
[[ -f "$ISO" ]] || { echo "!! ไม่ได้ไฟล์ ISO: ดูสาเหตุท้าย $WORK/build.log"; exit 1; }
DEST="$OUT/t3-$(date +%Y%m%d-%H%M)-amd64.iso"   # time in the name: never clashes with an ISO a VM still holds
cp "$ISO" "$DEST"; (cd "$OUT" && sha256sum "$(basename "$DEST")" > "$(basename "$DEST").sha256")
echo "OK: $DEST ($(du -h "$DEST" | cut -f1))"
