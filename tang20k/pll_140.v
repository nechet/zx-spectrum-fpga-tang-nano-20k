// -----------------------------------------------------------------------------
// Tang Nano 20K: 28 MHz pixel clock -> 140 MHz serialiser clock and 14 MHz
// board clock, cascaded off pll_28.
//
// 140 MHz cannot come from the 27 MHz crystal at all: 140/27 has no factor
// that keeps both the phase detector >= 3 MHz and the VCO <= 1200 MHz.  From
// 28 MHz it is a plain x5:
//
//   CLKOUT  = 28 * 5    = 140 MHz      phase detector 28 MHz -> OSER10 FCLK
//   VCO     = 140 * 8   = 1120 MHz     (400..1200)
//   CLKOUTD = 140 / 10  = 14.000 MHz   -> the board's master clock
//
// Taking 14 MHz from here rather than a flip-flop keeps it phase-locked to the
// 28 MHz pixel clock: one board line (896 clocks at 14 MHz) is then exactly two
// output lines (2 x 896 at 28 MHz), which is what stops the picture tearing.
// -----------------------------------------------------------------------------
`default_nettype none

module pll_140 (input wire clkin, output wire clkout, output wire clkout_div10,
                output wire lock);
  wire gnd = 1'b0;
  wire clkoutp_o, clkoutd3_o;

  rPLL rpll_inst (
      .CLKOUT(clkout), .LOCK(lock), .CLKOUTP(clkoutp_o),
      .CLKOUTD(clkout_div10), .CLKOUTD3(clkoutd3_o),
      .RESET(gnd), .RESET_P(gnd), .CLKIN(clkin), .CLKFB(gnd),
      .FBDSEL({gnd,gnd,gnd,gnd,gnd,gnd}), .IDSEL({gnd,gnd,gnd,gnd,gnd,gnd}),
      .ODSEL({gnd,gnd,gnd,gnd,gnd,gnd}), .PSDA({gnd,gnd,gnd,gnd}),
      .DUTYDA({gnd,gnd,gnd,gnd}), .FDLY({gnd,gnd,gnd,gnd}));

  defparam rpll_inst.FCLKIN = "28";
  defparam rpll_inst.DYN_IDIV_SEL = "false";
  defparam rpll_inst.IDIV_SEL = 0;          // /1  -> phase detector 28 MHz
  defparam rpll_inst.DYN_FBDIV_SEL = "false";
  defparam rpll_inst.FBDIV_SEL = 4;         // x5  -> 140 MHz
  defparam rpll_inst.DYN_ODIV_SEL = "false";
  defparam rpll_inst.ODIV_SEL = 8;          // VCO 1120 MHz
  defparam rpll_inst.DYN_SDIV_SEL = 10;     // 140 / 10 = 14.000 MHz
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
