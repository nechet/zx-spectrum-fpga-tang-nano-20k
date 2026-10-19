set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file -type verilog "defines.v"
add_file -type verilog "top20k.v"
add_file -type verilog "../ps2_rx.v"
add_file -type verilog "../ps2_zx_keymap.v"
add_file -type verilog "../zx_matrix.v"
add_file -type verilog "../sd_bridge.v"
add_file -type verilog "../sd_spi.v"
add_file -type verilog "../fat32.v"
add_file -type verilog "../nmi_gen.v"
add_file -type verilog "../ps2_keyboard.v"
add_file -type verilog "../../core/top.v"
add_file -type verilog "../scan_tripler.v"
add_file -type verilog "../../core/hdmi_out.v"
# HDMI with sound: the encoder from hdl-util/hdmi (apicula's copy of the same
# file has the data-island modes stubbed out), its packet modules, ours
add_file -type verilog "../third_party/hdmi/tmds_channel.sv"
add_file -type verilog "../third_party/hdmi/packet_picker.sv"
add_file -type verilog "../third_party/hdmi/packet_assembler.sv"
add_file -type verilog "../third_party/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "../third_party/hdmi/audio_sample_packet.sv"
add_file -type verilog "../third_party/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "../third_party/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "../third_party/hdmi/audio_info_frame.sv"
add_file -type verilog "../hdmi_audio_out.sv"
add_file -type verilog "../beeper_audio.v"
add_file -type verilog "../../core/gen/krasnodar48_synth.v"
add_file -type verilog "../../core/gen/fpga_memory.v"
add_file -type verilog "../../core/gen/lib_sync.v"
add_file -type verilog "../../core/gen/i8255.v"
add_file -type verilog "../../core/gen/z80_chip.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/synth/counters_sync.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/synth/synth_parts.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80n.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_core.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_alu.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_mcode.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_reg.v"
add_file -type verilog "../pll_405.v"
# The board pins, then the PS/2 keyboard's pair.  Choose the pair with the
# environment variable PS2_PINS: 73_74 (default, free header pins) or 25_26
# (shared with HDMI HPD/CEC).  Gowin uses only ONE .cst file -- given several
# it silently keeps the last -- so the two are concatenated into combined.cst.
set ps2_pins 73_74
if {[info exists ::env(PS2_PINS)]} { set ps2_pins $::env(PS2_PINS) }
puts "PS/2 keyboard pins: $ps2_pins"
set sfx [expr {$ps2_pins eq "73_74" ? "" : "_p$ps2_pins"}]
set out [open "combined.cst" w]
foreach f [list "tangnano20k_gowin.cst" "ps2_pins_$ps2_pins.cst"] {
  set in [open $f r]; puts $out [read $in]; close $in
}
close $out
add_file -type cst "combined.cst"
add_file -type sdc "krasnodar.sdc"
# The ROM: the 48K ROM with the loader menu patched in (mk_sdrom.py), written
# here as spectrum48.hex -- the name the board's ROM model loads.  Generated
# on every build; the original image is not touched.
exec python3 ../mk_sdrom.py ../../core/spectrum48.hex spectrum48.hex
set_option -top_module top20k
set_option -verilog_std sysv2017
set_option -output_base_name krasnodar_20k_sd720$sfx
set_option -use_sspi_as_gpio 1
set_option -looplimit 40000      ;# RAM48: 32768-cell power-up clear in dram_x1
set_option -place_option 1      ;# timing-driven placement
set_option -route_option 1
run all
