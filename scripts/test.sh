#!/bin/sh
# Run the simulations with the system's Icarus Verilog (iverilog, vvp on the
# PATH).  Another build can be chosen with IVERILOG=... VVP=...
#
#   scripts/test.sh          quick: line tripler, HDMI audio at 720p   (~10 min)
#   scripts/test.sh full     also the whole board: SD menu, .z80 load, .tap
#                            load, 720p frame check            (several hours)
#
# The whole-board tests need the ROM (scripts/get_rom.sh).
set -e
cd "$(dirname "$0")/.."
T=tang20k
run() { echo "=== $*"; "$@" 2>&1 | grep -v "sorry: constant selects" | grep -E "PASS|FAIL|ALL PASSED|FAILED|TIMEOUT"; }
run $T/tb_tripler.sh
run $T/tb_hdmi_audio.sh 720
if [ "$1" = full ]; then
  [ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts/get_rom.sh" >&2; exit 1; }
  run $T/tb_hdmi_audio.sh
  run $T/tb_sdmenu.sh
  run $T/tb_sdpage.sh
  run $T/tb_sdtap.sh
  run $T/tb_720p.sh
fi
