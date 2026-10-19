#!/bin/sh
# Build a bitstream with the Gowin toolchain (Gowin EDA 1.9.11; the free
# Education edition covers the Tang Nano 20K's GW2AR-18C).
#
#   export GOWIN=/path/to/gowin/IDE      the folder that holds bin/gw_sh
#   scripts/build.sh [720p|576p|<build folder>...]
#
#   720p (default)  1280x720 16:9, 3x3 pixels, sound, SD loader, PS/2 keyboard
#   576p            720x576 4:3, the same machine with the scan doubler
#
# Needs the ROM first (scripts/get_rom.sh), python3 and z80asm (the SD menu
# ROM is assembled during the build).  The result is printed at the end:
# tang20k/<build folder>/impl/pnr/*.fs
set -e
cd "$(dirname "$0")/.."
[ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts/get_rom.sh" >&2; exit 1; }
command -v z80asm >/dev/null || { echo "z80asm not found (Debian/Ubuntu: apt install z80asm)" >&2; exit 1; }
[ $# -gt 0 ] || set -- 720p
for t in "$@"; do
  case "$t" in
    720p) d=gowin_sd720 ;;
    576p) d=gowin_sd ;;
    *)    d=$t ;;
  esac
  tang20k/build.sh "$d"
done
