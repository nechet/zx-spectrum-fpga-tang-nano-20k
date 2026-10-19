set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file -type verilog "defines.v"
# TOP=sd_dump (step 1: card + raw sectors) or sd_list (step 2: FAT32 listing, default)
set top sd_list
if {[info exists ::env(TOP)]} { set top $::env(TOP) }
puts "SD test top: $top"
add_file -type verilog "../$top.v"
add_file -type verilog "../fat32.v"
add_file -type verilog "../sd_spi.v"
add_file -type verilog "../uart_tx.v"
add_file -type verilog "../../core/pll_135.v"
add_file -type cst "sdtest.cst"
add_file -type sdc "sdtest.sdc"
set_option -top_module $top
set_option -verilog_std sysv2017
set_option -output_base_name krasnodar_20k_[string map {sd_ sd} $top]
set_option -use_sspi_as_gpio 1
run all
