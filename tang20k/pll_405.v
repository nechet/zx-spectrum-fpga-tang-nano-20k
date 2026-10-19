// -----------------------------------------------------------------------------
// 27 MHz -> 405 MHz for the TMDS serialisers (FCLK = 5 x 81 MHz pixel clock),
// and 135 MHz for the board (CLKOUTD3 = 405 / 3).  One PLL for every clock.
//
//   CLKOUT = CLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 15 / 1 = 405 MHz
//   VCO    = CLKOUT * ODIV_SEL                    = 405 * 2    = 810 MHz
//   PFD    = 27 MHz
//
// 81 MHz is 6 x the board's 13.5 MHz, so a Spectrum line (896 board clocks)
// is exactly three HDMI lines of 1792 pixels: the 720p line tripler.
// CLKDIV /5 in the top level makes the pixel clock from CLKOUT.
// -----------------------------------------------------------------------------
`default_nettype none

module pll_405 (
    input  wire clkin,      // 27 MHz
    output wire clkout,     // 405 MHz
    output wire clkout_d3,  // 135 MHz
    output wire lock);

  wire gnd = 1'b0;
  wire clkoutp_o, clkoutd_o;

  rPLL rpll_inst (
      .CLKOUT   (clkout),
      .LOCK     (lock),
      .CLKOUTP  (clkoutp_o),
      .CLKOUTD  (clkoutd_o),
      .CLKOUTD3 (clkout_d3),
      .RESET    (gnd),
      .RESET_P  (gnd),
      .CLKIN    (clkin),
      .CLKFB    (gnd),
      .FBDSEL   ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .IDSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .ODSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .PSDA     ({gnd,gnd,gnd,gnd}),
      .DUTYDA   ({gnd,gnd,gnd,gnd}),
      .FDLY     ({gnd,gnd,gnd,gnd}));

  defparam rpll_inst.FCLKIN = "27";
  defparam rpll_inst.DYN_IDIV_SEL = "false";
  defparam rpll_inst.IDIV_SEL = 0;          // divide by 1
  defparam rpll_inst.DYN_FBDIV_SEL = "false";
  defparam rpll_inst.FBDIV_SEL = 14;        // multiply by 15
  defparam rpll_inst.DYN_ODIV_SEL = "false";
  defparam rpll_inst.ODIV_SEL = 2;          // VCO 810 MHz
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
  defparam rpll_inst.DYN_SDIV_SEL = 2;
  defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
  defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
  defparam rpll_inst.DEVICE = "GW2AR-18C";
endmodule
`default_nettype wire
