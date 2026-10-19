set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file -type verilog "defines.v"
add_file -type verilog "top20k.v"
add_file -type verilog "../ps2_rx.v"
add_file -type verilog "../ps2_zx_keymap.v"
add_file -type verilog "../zx_matrix.v"
add_file -type verilog "../ps2_keyboard.v"
add_file -type verilog "../../core/top.v"
add_file -type verilog "../../core/scan_doubler.v"
add_file -type verilog "../../core/hdmi_out.v"
add_file -type verilog "../../core/third_party/apicula/tmds_channel.v"
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
add_file -type verilog "../../core/pll_135.v"
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
set_option -top_module top20k
set_option -verilog_std sysv2017
set_option -output_base_name krasnodar_20k$sfx
set_option -use_sspi_as_gpio 1
set_option -looplimit 40000      ;# RAM48: 32768-cell power-up clear in dram_x1
run all
