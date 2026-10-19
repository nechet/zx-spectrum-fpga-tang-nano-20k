#!/bin/sh
# A real game through the .TAP loader: tb_sdmenu.v with -DTAP_TEST -DGAME_TAP,
# on the build's RTL with HDMI sound.  The tape (TAPE=..., default Manic
# Miner) goes into TINY.TAP's slot of the card image; the test passes when
# the CPU reaches the game's entry point (GAME_PC=..., default 8400 for
# Manic Miner's RANDOMIZE USR 33792).
set -e
cd "$(dirname "$0")"
TAPE=${TAPE:-../zx-games/tap/MANIC.TAP}
GAME_PC=${GAME_PC:-8400}
python3 mk_sdrom.py
# the card image next to the others (gitignored); paths stay short and
# relative: the memory models keep only the last 64 characters of a file name
TINY_TAP=$TAPE IMAGE_OUT=tb_game_image.hex EXPECT_OUT=/dev/null python3 mk_fat_image.py
L=../tang20k
cd ../core
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
H=$L/third_party/hdmi
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -DSD_LOADER -DRAM48 -DROM_BANKS -DTAP_TEST -DGAME_TAP -DHDMI_AUDIO -DMODEL_TECH \
    "-DGAME_PC=16'h$GAME_PC" "-DSD_IMAGE=\"$L/tb_game_image.hex\"" -DSD_SECTORS=512 \
    -o simsdgame $L/tb_sdmenu.v \
    $L/ps2_keyboard.v $L/ps2_rx.v $L/ps2_zx_keymap.v $L/zx_matrix.v \
    $L/sd_bridge.v $L/sd_spi.v $L/fat32.v $L/nmi_gen.v $L/sd_card_model.v \
    top.v scan_doubler.v $L/hdmi_audio_out.sv $L/beeper_audio.v \
    $H/tmds_channel.sv $H/packet_picker.sv $H/packet_assembler.sv \
    $H/audio_clock_regeneration_packet.sv $H/audio_sample_packet.sv \
    $H/auxiliary_video_information_info_frame.sv $H/source_product_description_info_frame.sv \
    $H/audio_info_frame.sv \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v
$VVP simsdgame +ROMFILE=$L/spectrum48_sd.hex
