#!/bin/sh
# Get the ZX Spectrum 48K ROM, check it, and write it where the builds and
# simulations read it.  The ROM is copyright Amstrad and is not part of this
# repository.  Amstrad allows it to be redistributed for emulation, and the
# Fuse emulator ships it on that basis, so by default it is fetched from
# Fuse's source tree.  Amstrad's statement (1999, archived by World of
# Spectrum):
#   https://web.archive.org/web/20160119110852/http://www.worldofspectrum.org/permits/amstrad-roms.txt
# "Amstrad have kindly given their permission for the redistribution of
# their copyrighted material but retain that copyright."
#
#   scripts/get_rom.sh            download (Fuse on SourceForge, then a mirror)
#   scripts/get_rom.sh 48.rom     use your own 16 KB image instead
#
# Either way the file must be the standard 48K ROM:
#   sha1 5ea7c2b824672e914525d1d5c419d71b84a426a2
set -e
cd "$(dirname "$0")/.."
SHA1=5ea7c2b824672e914525d1d5c419d71b84a426a2
URLS="https://sourceforge.net/p/fuse-emulator/fuse/ci/master/tree/roms/48.rom?format=raw
https://raw.githubusercontent.com/speccytools/fuse/master/roms/48.rom"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
if [ -n "$1" ]; then
  cp "$1" "$tmp"
else
  ok=
  for u in $URLS; do
    echo "fetching $u"
    if curl -fsSL --max-time 60 -o "$tmp" "$u"; then ok=1; break; fi
  done
  [ -n "$ok" ] || { echo "download failed; pass a 48.rom file instead" >&2; exit 1; }
fi
sum=$(sha1sum "$tmp" | cut -c1-40)
if [ "$sum" != "$SHA1" ]; then
  echo "not the standard 48K ROM: sha1 $sum, expected $SHA1" >&2; exit 1
fi
python3 Krasnodar-48-fpga/Tools/rom2hex.py "$tmp" core/spectrum48.hex
cp core/spectrum48.hex tang20k/gowin/spectrum48.hex
cp core/spectrum48.hex Krasnodar-48-fpga/rom/spectrum48.hex
echo "ROM ok (sha1 $sum): core/spectrum48.hex"
