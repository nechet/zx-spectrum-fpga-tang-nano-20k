#!/bin/sh
# The menu's paging: tb_sdmenu.v with -DPAGE_TEST and a ROM built with two
# games per page (MAXF=2), so the five-game test card spans three pages.
set -e
cd "$(dirname "$0")"
MAXF=2 python3 mk_sdrom.py ../core/spectrum48.hex spectrum48_sdp.hex
cd ../core
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
L=../tang20k
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -DSD_LOADER -DRAM48 -DROM_BANKS -DPAGE_TEST -o simsdpage $L/tb_sdmenu.v \
    $L/ps2_keyboard.v $L/ps2_rx.v $L/ps2_zx_keymap.v $L/zx_matrix.v \
    $L/sd_bridge.v $L/sd_spi.v $L/fat32.v $L/nmi_gen.v $L/sd_card_model.v \
    top.v scan_doubler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v
$VVP simsdpage +ROMFILE=$L/spectrum48_sdp.hex
