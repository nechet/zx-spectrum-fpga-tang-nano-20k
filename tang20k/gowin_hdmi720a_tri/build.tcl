set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file -type verilog "defines.v"
add_file -type verilog "../hdmi720_audio_test.v"
add_file -type verilog "../pll_405.v"
add_file -type verilog "../beeper_audio.v"
add_file -type verilog "../hdmi_audio_out.sv"
add_file -type verilog "../third_party/hdmi/tmds_channel.sv"
add_file -type verilog "../third_party/hdmi/packet_picker.sv"
add_file -type verilog "../third_party/hdmi/packet_assembler.sv"
add_file -type verilog "../third_party/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "../third_party/hdmi/audio_sample_packet.sv"
add_file -type verilog "../third_party/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "../third_party/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "../third_party/hdmi/audio_info_frame.sv"
add_file -type cst "../gowin_hdmi720/hdmi720.cst"
add_file -type sdc "../gowin_hdmi720/hdmi720.sdc"
set_option -top_module hdmi720_audio_test
set_option -verilog_std sysv2017
set_option -output_base_name hdmi720_audio_tri
set_option -use_sspi_as_gpio 1
run all
