set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file -type verilog "../hdmi720_test.v"
add_file -type verilog "../pll_371.v"
add_file -type verilog "../../core/hdmi_out.v"
add_file -type verilog "../../core/third_party/apicula/tmds_channel.v"
add_file -type cst "hdmi720.cst"
add_file -type sdc "hdmi720.sdc"
set_option -top_module hdmi720_test
set_option -verilog_std sysv2017
set_option -output_base_name hdmi720_test
set_option -use_sspi_as_gpio 1
run all
