// -----------------------------------------------------------------------------
// 27 MHz -> 371.25 MHz for 720p TMDS serialisers (FCLK = 5 x 74.25 MHz).
//
//   CLKOUT = CLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 55 / 4 = 371.25 MHz
//   VCO    = CLKOUT * ODIV_SEL                    = 371.25 * 2 = 742.5 MHz
//   PFD    = 27 / 4 = 6.75 MHz
//
// The same settings as Sipeed's TangNano-20K-example/hdmi (1280x720).
// CLKDIV /5 in the top level makes the 74.25 MHz pixel clock from this.
// -----------------------------------------------------------------------------
`default_nettype none

module pll_371 (
    input  wire clkin,      // 27 MHz
    output wire clkout,     // 371.25 MHz
    output wire lock);

  wire gnd = 1'b0;
  wire clkoutp_o, clkoutd_o, clkoutd3_o;

  rPLL rpll_inst (
      .CLKOUT   (clkout),
      .LOCK     (lock),
      .CLKOUTP  (clkoutp_o),
      .CLKOUTD  (clkoutd_o),
      .CLKOUTD3 (clkoutd3_o),
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
  defparam rpll_inst.IDIV_SEL = 3;          // divide by 4
  defparam rpll_inst.DYN_FBDIV_SEL = "false";
  defparam rpll_inst.FBDIV_SEL = 54;        // multiply by 55
  defparam rpll_inst.DYN_ODIV_SEL = "false";
  defparam rpll_inst.ODIV_SEL = 2;          // VCO 742.5 MHz
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
