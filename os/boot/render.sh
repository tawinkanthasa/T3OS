#!/usr/bin/env bash
# Render the T3 boot look (GRUB theme, Plymouth splash) from the SVGs next to this script.
#   render.sh grub OUTDIR [installed|live]
#   render.sh plymouth OUTDIR
# Needs rsvg-convert (librsvg2-bin), grub-mkfont (grub-common) and DejaVu fonts.
set -euo pipefail
B="$(cd "$(dirname "$0")" && pwd)"
what=$1 out=$2; mkdir -p "$out"
png() { rsvg-convert -w "$2" -h "$3" -o "$out/$1"; }   # SVG on stdin

# 9-slice rounded box for GRUB menu items: the nine pieces of one 40x40 box, radius 10
slices() { # prefix fill stroke
  local box="<rect x=\"0.5\" y=\"0.5\" width=\"39\" height=\"39\" rx=\"10\" fill=\"$2\" stroke=\"$3\"/>"
  local spec name x y w h
  for spec in nw:0:0:10:10 n:10:0:20:10 ne:30:0:10:10 w:0:10:10:20 c:10:10:20:20 e:30:10:10:20 \
              sw:0:30:10:10 s:10:30:20:10 se:30:30:10:10; do
    IFS=: read -r name x y w h <<<"$spec"
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$w\" height=\"$h\" viewBox=\"$x $y $w $h\">$box</svg>" \
      | png "$1_$name.png" "$w" "$h"
  done
}

case $what in
grub)
  mode=${3:-installed}
  rsvg-convert -w 1920 -h 1080 -o "$out/background.png" "$B/background.svg"
  rsvg-convert -w 72 -h 72 -o "$out/logo.png" "$B/logo.svg"
  slices select "rgba(63,185,80,0.16)" "rgba(63,185,80,0.55)"
  slices item "rgba(255,255,255,0.03)" "rgba(255,255,255,0.06)"
  slices term "#0e1511" "rgba(255,255,255,0.08)"
  F=/usr/share/fonts/truetype/dejavu
  for s in 13 14 16 18; do grub-mkfont -s "$s" -o "$out/dejavu-$s.pf2" "$F/DejaVuSansMono.ttf"; done
  grub-mkfont -s 18 -o "$out/dejavu-bold-18.pf2" "$F/DejaVuSansMono-Bold.ttf"
  if [[ $mode == live ]]; then title="T3  LIVE USB"; hint="Up/Down select   Enter boot"
  else title="CHOOSE A SYSTEM"; hint="Up/Down select   Enter boot   e edit"; fi
  sed -e "s/@TITLE@/$title/" -e "s/@HINT@/$hint/" "$B/grub/theme.txt.in" > "$out/theme.txt" ;;
plymouth)
  install -m 0644 "$B/plymouth/t3.plymouth" "$B/plymouth/t3.script" "$out/"
  rsvg-convert -w 1920 -h 1080 -o "$out/background.png" "$B/background.svg"
  rsvg-convert -w 112 -h 112 -o "$out/logo.png" "$B/logo.svg"
  echo '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><circle cx="4" cy="4" r="4" fill="#3fb950"/></svg>' \
    | png dot.png 8 8 ;;
*) echo "usage: render.sh grub|plymouth OUTDIR [installed|live]"; exit 2 ;;
esac
