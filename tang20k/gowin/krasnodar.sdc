// Timing constraints for the Tang Nano 20K build.
//
// The 27 MHz crystal; Gowin derives the PLL outputs (clk_x5 = 135 MHz) itself.
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


