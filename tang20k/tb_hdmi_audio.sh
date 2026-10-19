#!/bin/sh
# HDMI audio: hdmi_audio_out + beeper_audio, decoded as a monitor would (tb_hdmi_audio.v).
# ./tb_hdmi_audio.sh 720: the 720p build's raster and 81 MHz clock instead of 576p's.
set -e
cd "$(dirname "$0")"
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
H=third_party/hdmi
# MODEL_TECH: the vendored packets then send 0, not X, in their dont-care bytes
D=; [ "$1" = 720 ] && D=-DHDMI_720P
$IV -g2012 -DMODEL_TECH $D -o simhdmiaudio tb_hdmi_audio.v hdmi_audio_out.sv beeper_audio.v \
    $H/packet_picker.sv $H/packet_assembler.sv $H/audio_clock_regeneration_packet.sv \
    $H/audio_sample_packet.sv $H/auxiliary_video_information_info_frame.sv \
    $H/source_product_description_info_frame.sv $H/audio_info_frame.sv $H/tmds_channel.sv \
    ../core/pll_sim.v 2>&1 | grep -v "constant selects\|unique0* qualities" || true
$VVP simhdmiaudio
