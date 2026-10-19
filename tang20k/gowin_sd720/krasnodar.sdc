// Timing constraints for the Tang Nano 20K build.
//
// The 27 MHz crystal; Gowin derives the PLL outputs itself: 405 MHz (serialisers),
// 81 MHz (CLKDIV, pixels), 135 MHz (CLKOUTD3, clk_x5, the board).
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// The Z80 core runs on clk_x5 but only steps when its clock enable fires, once
// per board CLK rising edge -- every ~38 clk_x5 cycles at 3.5 MHz, and never
// closer than 8.  Its internal paths therefore have 8 cycles to settle, not
// one.  Without this Gowin treats ~380 of them as failing at 7.4 ns and spends
// placement effort on them at the expense of paths that really are one cycle.
// The register file (i_reg) is distributed RAM, written only on the same
// clock enable; its cells are not registers, so it is named by its pins.
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -setup -end 8
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -hold -end 7
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_pins {core/kras/U_D1/core/i_tv80_core/i_reg/*/DI*}] -setup -end 8
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_pins {core/kras/U_D1/core/i_tv80_core/i_reg/*/DI*}] -hold -end 7

// DRAM chips (fpga_memory.v): each pin is latched once (_1) and only trusted
// when the next latch agrees, so the board's gates have two clocks to settle
// into these flip-flops, not one.
set_multicycle_path -to [get_regs {core/kras/*/populated.ras_1* core/kras/*/populated.cas_1* core/kras/*/populated.we_1* core/kras/*/populated.d_1* core/kras/*/populated.a_1*}] -setup -end 2
set_multicycle_path -to [get_regs {core/kras/*/populated.ras_1* core/kras/*/populated.cas_1* core/kras/*/populated.we_1* core/kras/*/populated.d_1* core/kras/*/populated.a_1*}] -hold -end 1



// SD loader (sd_bridge.v): the card side runs on the 27 MHz board clock, the
// board on 135 MHz.  Gowin knows one is made from the other and would time
// the crossings as one-cycle paths; they are not.  Each is either a first
// synchroniser stage (STROBE, ACK) or a byte that is stable long before the
// toggle announcing it (command, answer).
set_false_path -to [get_regs {core/sdb/st_s*}]
set_false_path -to [get_regs {core/sdb/pb_s1*}]
set_false_path -to [get_regs {core/sdb/ack_s*}]
set_false_path -to [get_regs {core/sdb/pa_ext*}]

// HDMI sound (beeper_audio.v, hdmi_audio_out.sv).  The beeper and tape bits
// come from the board's 135 MHz logic into 27 MHz synchronisers: first stages.
set_false_path -to [get_regs {core/hdmi_gen.beep/spk_s* core/hdmi_gen.beep/tap_s*}]
// clk_audio is a 48 kHz clock made by a flip-flop.  Name it, so the paths it
// clocks are timed against its own 20.8 us period; the crossings between it
// and clk_pixel are synchronised inside packet_picker (toggle + two flops) or
// carry data that is stable for half an audio period around the edge.
create_clock -name clk_audio -period 20833.333 [get_nets {core/hdmi_gen.clk_audio}]
set_clock_groups -asynchronous -group [get_clocks {clk_audio}]

// 720p line tripler (scan_tripler.v): the board side runs on 135 MHz, the
// pixel side on 81 MHz.  Both come from the one 405 MHz PLL, so Gowin times
// the crossings as related clocks, whose edges can be as little as 2.5 ns
// apart.  They are not one-cycle paths: each is the first stage of a
// two-flop synchroniser (line sync, frame sync, buffer select).  The line
// buffer itself is a dual-clock block RAM, written and read on its own ports.
set_false_path -to [get_regs {core/dbl/hs_m* core/dbl/vs_m* core/dbl/wbuf_m*}]
// The board reset into the 135 MHz domain: the first synchroniser stage.
set_false_path -to [get_regs {core/res_s_0*}]
// The serialisers' reset, released once at power-up, on the pixel clock.
// OSER10's RESET is asynchronous; a release a fast-clock cycle apart on
// different lanes only shifts that lane's word by a bit, which the monitor's
// per-lane word alignment absorbs.
set_false_path -from [get_regs {core/tmdsrst*}]

// Full list of the worst paths, so failures outside the Z80 are visible.
report_timing -setup -max_paths 300 -max_common_paths 1
