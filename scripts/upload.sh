#!/bin/sh
# Load a bitstream into the Tang Nano 20K with openFPGALoader.
#
#   scripts/upload.sh [sram|flash] [file.fs]
#
#   sram  (default)  into the FPGA's configuration memory: runs at once,
#                    gone at power-off -- for trying a build
#   flash            into the board's SPI flash: loaded at every power-up
#
# The default file is the 720p build's output.  If the board is not found,
# check the USB cable and that your user may open the device (udev rules,
# see openFPGALoader's documentation).
set -e
cd "$(dirname "$0")/.."
mode=${1:-sram}
fs=${2:-tang20k/gowin_sd720/impl/pnr/krasnodar_20k_sd720.fs}
[ -f "$fs" ] || { echo "no bitstream $fs: run scripts/build.sh first" >&2; exit 1; }
case "$mode" in
  sram)  openFPGALoader -b tangnano20k "$fs" ;;
  flash) openFPGALoader -b tangnano20k -f "$fs" ;;
  *)     echo "usage: $0 [sram|flash] [file.fs]" >&2; exit 1 ;;
esac
