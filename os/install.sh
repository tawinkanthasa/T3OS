#!/usr/bin/env bash
# Install the T3 desktop files into a root filesystem.
#   sudo os/install.sh            -> this machine (/)
#   os/install.sh /some/chroot    -> an ISO chroot, or a throwaway tree for the WSL trial
# Packages come separately (os/packages/*.list). Safe to re-run.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$SRC")"; K="$SRC/kde"
ROOT="${1:-/}"; ROOT="${ROOT%/}"
T3="$ROOT/usr/share/t3"; SHARE="$ROOT/usr/share"; XDG="$ROOT/etc/xdg"

install -d "$T3/bin" "$T3/wallpapers" "$SHARE/plasma/look-and-feel" "$SHARE/plasma/plasmoids" \
           "$SHARE/color-schemes" "$SHARE/applications" "$SHARE/icons/hicolor/scalable/apps" \
           "$XDG/autostart" "$ROOT/etc/sddm.conf.d" "$SHARE/sddm/themes/breeze" \
           "$T3/udev" "$ROOT/etc/udev/rules.d" "$SHARE/wayland-sessions" \
           "$SHARE/icons" "$SHARE/aurorae/themes" "$SHARE/wallpapers"
install -m 0755 "$SRC"/bin/* "$T3/bin/"
cp -r "$REPO/ui" "$T3/"
install -m 0644 "$K"/wallpapers/* "$T3/wallpapers/"
rm -rf "$SHARE/plasma/look-and-feel/org.t3.desktop" "$SHARE/plasma/plasmoids/org.t3.boards"
cp -r "$K/look-and-feel/org.t3.desktop" "$SHARE/plasma/look-and-feel/"
cp -r "$K/plasmoids/org.t3.boards" "$SHARE/plasma/plasmoids/"
install -m 0644 "$K"/color-schemes/* "$SHARE/color-schemes/"
install -m 0644 "$K"/applications/* "$SHARE/applications/"
# One settings app: T3 Settings. KDE's System Settings stays installed (T3 Settings links to it, and
# KDE's own "Configure..." buttons use it) but is hidden from the menu and search. A copy in
# /usr/local/share wins over /usr/share and survives KDE updates.
if [[ -f "$SHARE/applications/systemsettings.desktop" ]]; then
  install -d "$ROOT/usr/local/share/applications"
  sed '0,/^\[Desktop Entry\]$/s//[Desktop Entry]\nNoDisplay=true/' "$SHARE/applications/systemsettings.desktop" \
    > "$ROOT/usr/local/share/applications/systemsettings.desktop"
fi
install -m 0644 "$K"/icons/* "$SHARE/icons/hicolor/scalable/apps/"
# the design's look: dock tiles (icon theme), red/yellow/green window buttons, wallpaper package
rm -rf "$SHARE/icons/T3" "$SHARE/aurorae/themes/T3" "$SHARE/wallpapers/T3"
cp -r "$K/icons-theme/T3" "$SHARE/icons/"
cp -r "$K/aurorae/T3" "$SHARE/aurorae/themes/"
cp -r "$K/wallpaper-pkg/T3" "$SHARE/wallpapers/"
install -d "$SHARE/kwin/scripts"
for d in "$K"/kwin-scripts/*/; do n=$(basename "$d"); rm -rf "$SHARE/kwin/scripts/$n"; cp -r "$d" "$SHARE/kwin/scripts/$n"; done
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf "$SHARE/icons/T3" 2>/dev/null || true
for f in kwinrc kglobalshortcutsrc kxkbrc plasmanotifyrc plasmarc ksplashrc kscreenlockerrc kcm-about-distrorc; do install -m 0644 "$K/xdg/$f" "$XDG/$f"; done
install -m 0644 "$K"/xdg/autostart/* "$XDG/autostart/"
# KDE reads colours from kdeglobals itself, so the scheme's groups are appended to the defaults
{ cat "$K/xdg/kdeglobals"; grep -v '^\[General\]$\|^ColorScheme=\|^Name=\|^shadeSortColumn=' "$K/color-schemes/T3Dark.colors"; } > "$XDG/kdeglobals"
install -m 0644 "$K/sddm/t3.conf" "$ROOT/etc/sddm.conf.d/t3.conf"
install -m 0644 "$K/sddm/theme.conf.user" "$SHARE/sddm/themes/breeze/theme.conf.user"
rm -rf "$SHARE/sddm/themes/t3"; cp -r "$K/sddm-theme/t3" "$SHARE/sddm/themes/"   # T3 login screen
install -m 0644 "$K"/sessions/* "$SHARE/wayland-sessions/"
# boards/probes usable without sudo (also kept in /usr/share/t3 so T3 Doctor can reinstall it)
install -m 0644 "$SRC/udev/99-t3-boards.rules" "$T3/udev/"
install -m 0644 "$SRC/udev/99-t3-boards.rules" "$ROOT/etc/udev/rules.d/"
# which T3 this is (T3 Doctor, update check)
{ cat "$REPO/COMMIT" 2>/dev/null || git -C "$REPO" rev-parse --short=12 HEAD 2>/dev/null || echo unknown; date -u +%Y-%m-%d; } | paste -sd' ' - > "$T3/VERSION"

if [[ "$ROOT" != "" && "${T3_KEEP_PATHS:-}" != 1 ]]; then
  # installed somewhere other than /: point every reference at that tree
  grep -rlI /usr/share/t3 "$T3/bin" "$SHARE/plasma" "$SHARE/applications" "$SHARE/sddm" "$SHARE/wayland-sessions" "$XDG/autostart" 2>/dev/null \
    | xargs -r sed -i "s#/usr/share/t3#$T3#g"
fi
command -v gtk-update-icon-cache >/dev/null && [[ -z "$ROOT" ]] && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
echo "T3 desktop files installed into ${ROOT:-/}"
