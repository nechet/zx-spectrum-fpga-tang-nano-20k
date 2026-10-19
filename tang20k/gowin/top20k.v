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
    input  wire       ps2_data);    // PS/2 keyboard DATA, pin 74

  top #(.WITH_HDMI(1), .TRUE_LVDS(1), .RST_ACTIVE_LOW(0)) core (
      .clk(clk), .rst_i(rst_i), .led(led),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
      .ps2_clk(ps2_clk), .ps2_data(ps2_data));
endmodule
`default_nettype wire
