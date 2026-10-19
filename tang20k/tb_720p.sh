#!/bin/sh
# Whole board on the 720p build (scan_tripler.v): boot, F12, the menu, then
# one 1280 x 720 frame captured from the tripler and checked pixel by pixel
# against the screen memory and the border (tb_sdmenu.v, FRAME_TEST).
# Leaves the frame as frame720.ppm here.
set -e
cd "$(dirname "$0")"
python3 mk_sdrom.py
L=../tang20k
cd ../core
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -DSD_LOADER -DRAM48 -DROM_BANKS -DHDMI_720P -DFRAME_TEST -o sim720p $L/tb_sdmenu.v \
    $L/ps2_keyboard.v $L/ps2_rx.v $L/ps2_zx_keymap.v $L/zx_matrix.v \
    $L/sd_bridge.v $L/sd_spi.v $L/fat32.v $L/nmi_gen.v $L/sd_card_model.v \
    top.v $L/scan_tripler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v $L/sim_720p.v
$VVP sim720p +ROMFILE=$L/spectrum48_sd.hex
mv -f frame720.ppm $L/ 2>/dev/null || true
