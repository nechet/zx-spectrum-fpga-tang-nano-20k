#!/bin/sh
# Build one Gowin project and check the result:  ./build.sh gowin [gowin_ps2leds ...]
#
# Gowin's gw_sh exits 0 even when synthesis reports an ERROR -- it turns the
# failing module into an empty black box and carries on, or leaves the old
# bitstream in place.  So this fails on any ERROR line, on a bitstream that is
# not newer than the start of the build, and prints the BSRAM use and every
# I/O's lock state for a look.
set -e
G=${GOWIN:?"set GOWIN to the Gowin IDE folder (the one holding bin/gw_sh), e.g. export GOWIN=\$HOME/gowin/IDE"}
cd "$(dirname "$0")"
for p in "$@"; do
  echo "== $p"
  stamp=$(mktemp)
  ( cd "$p" && env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE \
      LD_LIBRARY_PATH=$G/lib QT_PLUGIN_PATH=$G/plugins/qt QT_QPA_PLATFORM=offscreen \
      LIBGL_ALWAYS_SOFTWARE=1 $G/bin/gw_sh build.tcl > build.log 2>&1 ) || true
  if grep -n "^ERROR" "$p/build.log"; then echo "FAILED: errors above ($p/build.log)"; exit 1; fi
  fs=$(ls -t "$p"/impl/pnr/*.fs | head -1)        # newest, if the output name changed
  if [ ! "$fs" -nt "$stamp" ]; then echo "FAILED: $fs not rewritten"; exit 1; fi
  rm -f "$stamp"
  echo "$fs"
  # Timing: Gowin reports failing paths but still writes the bitstream.
  python3 - "$p" <<'PY'
import re, html, glob, sys
f = max(glob.glob(sys.argv[1] + '/impl/pnr/*_tr_content.html'), key=lambda x: __import__('os').path.getmtime(x))
t = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', open(f, errors='ignore').read())))
for m in re.finditer(r'(\S+) Setup (-[0-9.]+) ([0-9]+)', t):
    print('TIMING FAILS: %s setup TNS %s ns on %s endpoints' % m.groups())
for m in re.finditer(r'(\S+) ([0-9.]+)\(MHz\) ([0-9.]+)\(MHz\)', t):
    print('  %s: constraint %s MHz, Fmax %s MHz' % m.groups())
PY
  rpt=${fs%.fs}.rpt.txt
  grep -E "^ *(Logic|Register|BSRAM) " "$rpt" | sed 's/  */ /g'
  grep -E "^(clk|rst_i|ps2_|tmds|led|uart|sd_|nmi_)" "$rpt" | awk -F'|' '{gsub(/ /, ""); printf "%s %s %s %s; ", $1, $3, $4, $8} END {print ""}'
done
