#!/bin/sh
# Integration test of the upper 32K of RAM in the whole board (testrom5).
# DEFS=-DRAM48 for the 48K build (the 20K default); without it, a 16K machine,
# which this test should fail.
set -e
cd "$(dirname "$0")/../core"
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 ${DEFS--DRAM48} -o simram48 ../tang20k/tb_ram48.v \
    top.v scan_doubler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v
$VVP simram48 +ROMFILE=../tang20k/testrom5.hex
