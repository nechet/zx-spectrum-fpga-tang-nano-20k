// -----------------------------------------------------------------------------
// Tang Nano 20K: 27 MHz crystal -> 28.000 MHz pixel clock.
//
// 28 MHz direct would need 27*28/27, IDIV+1 = 27, a 1 MHz phase detector --
// below the 3 MHz minimum.  So multiply first and divide after, the same trick
// as ../core/pll_14.v:
//
//   CLKOUT  = 27/3 * 28 = 252 MHz      phase detector 9 MHz
//   VCO     = 252 * 4   = 1008 MHz     (400..1200)
//   CLKOUTD = 252 / 9   = 28.000 MHz   <- the only output used
//
// 28 MHz pixel with the board at 14 MHz gives 896 / 28 MHz = 32 us lines,
// i.e. 31.25 kHz / 50.08 Hz -- 576p50's rates, which the monitor accepts --
// instead of the 30.13 kHz / 48.29 Hz that 27 MHz gives and it refuses.
// -----------------------------------------------------------------------------
`default_nettype none

module pll_28 (input wire clkin, output wire clkout, output wire lock);
  wire gnd = 1'b0;
  wire clkout_fast, clkoutp_o, clkoutd3_o;

  rPLL rpll_inst (
      .CLKOUT(clkout_fast), .LOCK(lock), .CLKOUTP(clkoutp_o),
      .CLKOUTD(clkout), .CLKOUTD3(clkoutd3_o),
      .RESET(gnd), .RESET_P(gnd), .CLKIN(clkin), .CLKFB(gnd),
      .FBDSEL({gnd,gnd,gnd,gnd,gnd,gnd}), .IDSEL({gnd,gnd,gnd,gnd,gnd,gnd}),
      .ODSEL({gnd,gnd,gnd,gnd,gnd,gnd}), .PSDA({gnd,gnd,gnd,gnd}),
      .DUTYDA({gnd,gnd,gnd,gnd}), .FDLY({gnd,gnd,gnd,gnd}));

  defparam rpll_inst.FCLKIN = "27";
  defparam rpll_inst.DYN_IDIV_SEL = "false";
  defparam rpll_inst.IDIV_SEL = 2;          // /3  -> phase detector 9 MHz
  defparam rpll_inst.DYN_FBDIV_SEL = "false";
  defparam rpll_inst.FBDIV_SEL = 27;        // x28 -> 252 MHz
  defparam rpll_inst.DYN_ODIV_SEL = "false";
  defparam rpll_inst.ODIV_SEL = 4;          // VCO 1008 MHz
  defparam rpll_inst.DYN_SDIV_SEL = 9;      // 252 / 9 = 28.000 MHz
  defparam rpll_inst.PSDA_SEL = "0000";
  defparam rpll_inst.DYN_DA_EN = "true";
  defparam rpll_inst.DUTYDA_SEL = "1000";
  defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
  defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
  defparam rpll_inst.CLKOUT_DLY_STEP = 0;
  defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
  defparam rpll_inst.CLKFB_SEL = "internal";
  defparam rpll_inst.CLKOUT_BYPASS = "false";
  defparam rpll_inst.CLKOUTP_BYPASS = "false";
  defparam rpll_inst.CLKOUTD_BYPASS = "false";
  defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
  defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
  defparam rpll_inst.DEVICE = "GW2A-18C";
endmodule
`default_nettype wire
