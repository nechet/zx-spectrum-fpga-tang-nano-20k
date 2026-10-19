// -----------------------------------------------------------------------------
// 720p HDMI sound test: colour bars and a beeping 1 kHz tone (half a second
// on, half off), through the same hdmi_audio_out + beeper_audio as the
// Spectrum build.  Which timing is a build-time choice (gowin_hdmi720a/*):
//
//   A720P60   1650 x 750 at 74.25 MHz, CEA 720p60 (VIC 4)
//   A720P50   1980 x 750 at 74.25 MHz, CEA 720p50 (VIC 19)
//   ATRIPLER  1792 x 936 at 81 MHz, the Spectrum build's raster (VIC 0)
//
// So if the monitor plays sound on a standard mode but not on the tripler's,
// the timing is what it objects to, not the audio path.
// -----------------------------------------------------------------------------
`default_nettype none

module hdmi720_audio_test (
    input  wire       clk,          // 27 MHz, pin 4
    input  wire       btn,          // S2, unused (the shared .cst names it)
    output wire [5:0] led,          // active low
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n);

`ifdef ATRIPLER
  localparam H_TOTAL = 1792, V_TOTAL = 936, VIC = 0, DIV = 3;
  localparam real RATE = 81.0E6;
  wire clk_x5, clk_sys, lock;
  pll_405 pll (.clkin(clk), .clkout(clk_x5), .clkout_d3(clk_sys), .lock(lock));
`else
`ifdef A720P50
  localparam H_TOTAL = 1980, V_TOTAL = 750, VIC = 19;
`else
  localparam H_TOTAL = 1650, V_TOTAL = 750, VIC = 4;
`endif
  localparam DIV = 3;               // 74.25 / 3 = 24.75 MHz: beeper's 48 kHz 8% low, fine here
  localparam real RATE = 74.25E6;
  wire clk_x5, lock;
  pll_371 pll (.clkin(clk), .clkout(clk_x5), .lock(lock));
`endif
  wire clk_pixel;
  CLKDIV #(.DIV_MODE("5"), .GSREN("false")) div5 (
      .CLKOUT(clk_pixel), .HCLKIN(clk_x5), .RESETN(lock), .CALIB(1'b0));

  reg [11:0] rst_cnt = 12'd0;
  always @(posedge clk_pixel or negedge lock)
    if (!lock) rst_cnt <= 12'd0;
    else if (!(&rst_cnt)) rst_cnt <= rst_cnt + 12'd1;
  wire reset = ~(&rst_cnt);

  // raster: active 1280 x 720, sync 40 pixels before a 220-pixel back porch
  reg [10:0] cx = 11'd0;
  reg [9:0]  cy = 10'd0;
  always @(posedge clk_pixel)
    if (cx == H_TOTAL - 1) begin
      cx <= 11'd0;
      cy <= (cy == V_TOTAL - 1) ? 10'd0 : cy + 10'd1;
    end else
      cx <= cx + 11'd1;
  wire hs = cx >= H_TOTAL - 260 && cx < H_TOTAL - 220;
  wire vs = cy >= 725 && cy < 730;
  wire [2:0] bar = cx[10:8] + cx[7];          // ~eight bars across 1280
  wire [7:0] r = bar[0] ? 8'hCD : 8'h00, g = bar[1] ? 8'hCD : 8'h00, b = bar[2] ? 8'hCD : 8'h00;

  // the tone: 1 kHz square, gated on and off every half second
  reg [26:0] t = 27'd0;
  always @(posedge clk_pixel) t <= t + 27'd1;
  reg [15:0] tdiv = 16'd0;
  reg        spk = 1'b0;
  always @(posedge clk_pixel)
    if (tdiv == RATE / 2000 - 1) begin tdiv <= 16'd0; spk <= ~spk & ~t[25]; end
    else tdiv <= tdiv + 16'd1;

  wire        clk_audio;
  wire [15:0] audio;
  beeper_audio #(.CLK_DIV(DIV)) beep (.clk_pixel(clk_pixel), .speaker(spk), .tape(1'b0),
                                      .clk_audio(clk_audio), .sample(audio));
  hdmi_audio_out #(.TRUE_LVDS(1), .H_ACTIVE(1280), .H_TOTAL(H_TOTAL), .V_ACTIVE(720),
                   .V_TOTAL(V_TOTAL), .VIDEO_ID_CODE(VIC), .VIDEO_RATE(RATE)) hdmi (
      .clk_pixel(clk_pixel), .clk_x5(clk_x5), .reset(reset), .cx(cx), .cy(cy),
      .red(r), .green(g), .blue(b), .hsync_tx(hs), .vsync_tx(vs),
      .clk_audio(clk_audio), .audio_l(audio), .audio_r(audio),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n));

  assign led = ~{t[26], 4'b0000, lock};
endmodule
`default_nettype wire
