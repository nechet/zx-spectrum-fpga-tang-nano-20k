#!/bin/sh
# Unit test of the 720p line tripler (scan_tripler.v) on a synthetic raster.
set -e
cd "$(dirname "$0")"
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
$IV -g2012 -o simtripler tb_tripler.v scan_tripler.v
$VVP simtripler
