#!/bin/sh
# Integration test of the PS/2 keyboard in the whole board (testrom4).
set -e
cd "$(dirname "$0")/../core"
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -o simkbdsys ../tang20k/tb_kbd_sys.v \
    ../tang20k/ps2_keyboard.v ../tang20k/ps2_rx.v \
    ../tang20k/ps2_zx_keymap.v ../tang20k/zx_matrix.v \
    top.v scan_doubler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v
$VVP simkbdsys +ROMFILE=../tang20k/testrom4.hex
