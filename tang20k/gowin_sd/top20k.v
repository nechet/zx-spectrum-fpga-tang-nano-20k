// Tang Nano 20K top level for the Gowin toolchain.
//
// Why a wrapper: the open-source flow (yosys + nextpnr + apicula) sets top's
// parameters with chparam, but on the GW2A-18C apicula has an unresolved
// placement-dependent miscompute bug (YosysHQ/apicula#541) -- and that is what
// left this board's video timing dead on the 20K while it ran in simulation.
// Gowin's own tools avoid it; this wrapper just fixes the two board-specific
// parameters without touching top.v.
`default_nettype none
module top20k (
    input  wire       clk,          // 27 MHz, pin 4
    input  wire       rst_i,        // button, pin 88, idles low on this board
    output wire [5:0] led,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    input  wire       ps2_clk,      // PS/2 keyboard CLK, pin 73
    input  wire       ps2_data,     // PS/2 keyboard DATA, pin 74
    output wire       sd_clk,       // microSD, SPI mode: pins 83, 82, 81, 84
    output wire       sd_cmd,
    output wire       sd_dat3,
    input  wire       sd_dat0,
    input  wire       nmi_btn);     // button S2, pin 87: loader menu

  top #(.WITH_HDMI(1), .TRUE_LVDS(1), .RST_ACTIVE_LOW(0)) core (
      .clk(clk), .rst_i(rst_i), .led(led),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
      .ps2_clk(ps2_clk), .ps2_data(ps2_data),
      .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat3(sd_dat3), .sd_dat0(sd_dat0),
      .nmi_btn(nmi_btn));
endmodule
`default_nettype wire
