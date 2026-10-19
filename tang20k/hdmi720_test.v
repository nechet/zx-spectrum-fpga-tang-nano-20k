// -----------------------------------------------------------------------------
// 1280x720 HDMI test: does the monitor take the raster a frame-locked 720p
// Spectrum picture would need, and how does the layout look?
//
// Button S2 steps through four timings, all at a 74.25 MHz pixel clock:
//
//   mode  total       rate       scale  LEDs lit  what
//    0    1664 x 924  48.29 Hz   3x3    1         frame-locked, the candidate
//    1    2002 x 768  48.29 Hz   2x2    2         frame-locked, the first try
//    2    1980 x 750  50.00 Hz   3x3    3         CEA-861 720p50 (VIC 19)
//    3    1650 x 750  60.00 Hz   3x3    4         CEA-861 720p60 (VIC 4)
//
// Frame-locked: one Spectrum frame is 896 x 312 clocks of the board's
// 13.5 MHz, which is 896 x 312 x 5.5 = 1 537 536 clocks of 74.25 MHz.  Both
// 1664 x 924 and 2002 x 768 are exactly that, so HDMI frames and Spectrum
// frames would stay in step for ever, as the 576p output does now.
//
// Why 1664 for 3x3: three HDMI lines per Spectrum line want 4928 / 3 = 1642.7
// clocks each.  1664 is the nearest whole number that divides the frame, so
// the HDMI side falls behind by only ~3 Spectrum lines over the picture --
// a line buffer of a few lines (one block RAM) absorbs that.
//
// The picture is the planned layout.  At 3x3: the 256 x 192 paper is
// 768 x 576 (80% of the height), 24 Spectrum border lines show above and
// below, and the 16:9 sides are border.  At 2x2: the 352 x 288 visible area
// is 704 x 576 in the middle.  Inside the paper: colour bars, a
// one-Spectrum-pixel checkerboard (sharp on a good monitor) and a grey ramp.
// A white 1-pixel frame marks the screen's outermost pixels, to see whether
// the monitor crops (overscan).  The border is blue; the edges of the
// Spectrum's own 352-pixel-wide area are dotted lines, to show how much of
// the width is the extension.
//
// Built with PIX81 defined (gowin_hdmi720, PIX=81): one PLL makes 405 MHz,
// the pixel clock is 81 MHz and mode 0 is 1792 x 936 -- 81 MHz is 6 x the
// board's 13.5 MHz, so each Spectrum line is exactly three HDMI lines.  The
// PLL's 135 MHz output (the board clock in the real design) blinks LED 5.
// Modes 1..3 keep their totals, so their rates scale by 81 / 74.25.
// -----------------------------------------------------------------------------
`default_nettype none

module hdmi720_test (
    input  wire       clk,          // 27 MHz, pin 4
    input  wire       btn,          // S2, pin 87, high while pressed
    output wire [5:0] led,          // active low
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n);

  // --- clocks ----------------------------------------------------------------
  wire clk_x5, lock, clk_pixel;
`ifdef PIX81
  wire clk_sys;
  pll_405 pll (.clkin(clk), .clkout(clk_x5), .clkout_d3(clk_sys), .lock(lock));
  reg [26:0] blink = 27'd0;                 // ~1 s at 135 MHz
  always @(posedge clk_sys) blink <= blink + 27'd1;
  wire led5 = blink[26];
  localparam [11:0] H0 = 12'd1792;
  localparam [9:0]  V0 = 10'd936;
`else
  pll_371 pll (.clkin(clk), .clkout(clk_x5), .lock(lock));
  wire led5 = 1'b0;
  localparam [11:0] H0 = 12'd1664;
  localparam [9:0]  V0 = 10'd924;
`endif
  CLKDIV #(.DIV_MODE("5"), .GSREN("false")) div5 (
      .CLKOUT(clk_pixel), .HCLKIN(clk_x5), .RESETN(lock), .CALIB(1'b0));

  reg [3:0] rst_cnt = 4'd0;
  always @(posedge clk_pixel or negedge lock)
    if (!lock) rst_cnt <= 4'd0;
    else if (!rst_cnt[3]) rst_cnt <= rst_cnt + 4'd1;
  wire reset = !rst_cnt[3];

  // --- mode button: synchronise, debounce (~14 ms), step on press ------------
  reg [1:0]  btn_s = 2'b00;
  reg [19:0] deb   = 20'd0;
  reg        btn_d = 1'b0, btn_q = 1'b0;
  reg [1:0]  mode  = 2'd0;
  always @(posedge clk_pixel) begin
    btn_s <= {btn_s[0], btn};
    if (btn_s[1] == btn_d) deb <= 20'd0;
    else if (&deb) begin btn_d <= btn_s[1]; deb <= 20'd0; end
    else deb <= deb + 20'd1;
    btn_q <= btn_d;
    if (btn_d && !btn_q) mode <= mode + 2'd1;
  end
  assign led = ~{led5, 1'b0, mode == 2'd3, mode >= 2'd2, mode >= 2'd1, 1'b1};
  wire x2 = (mode == 2'd1);

  // --- timing -----------------------------------------------------------------
  localparam H_ACT = 1280, H_SYNC = 40, H_BACK = 220;
  localparam V_ACT = 720,  V_FRONT = 5, V_SYNC = 5;
  reg [11:0] h_total;
  reg [9:0]  v_total;
  always @(*)
    case (mode)
      2'd0:    begin h_total = H0;       v_total = V0;       end
      2'd1:    begin h_total = 12'd2002; v_total = 10'd768; end
      2'd2:    begin h_total = 12'd1980; v_total = 10'd750; end
      default: begin h_total = 12'd1650; v_total = 10'd750; end
    endcase

  reg [11:0] cx = 12'd0;
  reg [9:0]  cy = 10'd0;
  always @(posedge clk_pixel)
    if (reset) begin cx <= 12'd0; cy <= 10'd0; end
    else if (cx >= h_total - 12'd1) begin
      cx <= 12'd0;
      cy <= (cy >= v_total - 10'd1) ? 10'd0 : cy + 10'd1;
    end else
      cx <= cx + 12'd1;

  // Sync just before the back porch, at the end of the line, so the front
  // porch takes up whatever is left: positive polarity, as 720p specifies.
  wire hsync  = (cx >= h_total - H_BACK - H_SYNC) && (cx < h_total - H_BACK);
  wire vsync  = (cy >= V_ACT + V_FRONT) && (cy < V_ACT + V_FRONT + V_SYNC);
  wire active = (cx < H_ACT) && (cy < V_ACT);

  // --- layout -----------------------------------------------------------------
  // 3x3: Spectrum area 1056 wide from x 112; paper 768 x 576 at (256, 72).
  // 2x2: Spectrum area 704 x 576 at (288, 72); paper 512 x 384 at (384, 168).
  wire [11:0] sx0 = x2 ? 12'd288 : 12'd112,  sx1 = x2 ? 12'd992 : 12'd1168;
  wire [11:0] px0 = x2 ? 12'd384 : 12'd256,  px1 = x2 ? 12'd896 : 12'd1024;
  wire [9:0]  py0 = x2 ? 10'd168 : 10'd72,   py1 = x2 ? 10'd552 : 10'd648;
  wire [9:0]  sy0 = x2 ? 10'd72  : 10'd0,    sy1 = x2 ? 10'd648 : 10'd720;

  // Spectrum-pixel counters across the paper: sub counts screen pixels within
  // one Spectrum pixel (0..scale-1), sp counts Spectrum pixels.  Counters, not
  // cx / 3, which would need a divider.
  reg [1:0] hsub = 2'd0, vsub = 2'd0;
  reg [7:0] hsp  = 8'd0, vsp  = 8'd0;
  wire [1:0] last = x2 ? 2'd1 : 2'd2;
  always @(posedge clk_pixel) begin
    if (cx == px0 - 12'd1) begin hsub <= 2'd0; hsp <= 8'd0; end
    else if (hsub == last) begin hsub <= 2'd0; hsp <= hsp + 8'd1; end
    else hsub <= hsub + 2'd1;
    if (cx == h_total - 12'd1) begin
      if (cy == {2'b00, py0} - 10'd1 || cy == v_total - 10'd1) begin vsub <= 2'd0; vsp <= 8'd0; end
      else if (vsub == last) begin vsub <= 2'd0; vsp <= vsp + 8'd1; end
      else vsub <= vsub + 2'd1;
    end
  end

  wire edge_px  = (cx == 0) || (cx == H_ACT - 1) || (cy == 0) || (cy == V_ACT - 1);
  wire outline  = (((cx == sx0 - 12'd1) || (cx == sx1)) && (cy >= sy0) && (cy < sy1) ||
                   ((cy == sy0 - 10'd1) || (cy == sy1)) && x2 && (cx >= sx0) && (cx < sx1))
                  && (cx[2] ^ cy[2]);
  wire in_paper = (cx >= px0) && (cx < px1) && (cy >= py0) && (cy < py1);

  reg [23:0] rgb;
  always @(*) begin
    if (edge_px)                 rgb = 24'hFFFFFF;
    else if (outline)            rgb = 24'hCDCDCD;
    else if (!in_paper)          rgb = 24'h0000CD;          // Spectrum blue border
    else if (vsp < 8'd96)                                    // 8 bars of 32 Spectrum pixels
      case (hsp[7:5])
        3'd0: rgb = 24'hCDCDCD;  3'd1: rgb = 24'hCDCD00;
        3'd2: rgb = 24'h00CDCD;  3'd3: rgb = 24'h00CD00;
        3'd4: rgb = 24'hCD00CD;  3'd5: rgb = 24'hCD0000;
        3'd6: rgb = 24'h0000CD;  default: rgb = 24'h000000;
      endcase
    else if (vsp < 8'd160)       rgb = (hsp[0] ^ vsp[0]) ? 24'hFFFFFF : 24'h000000;
    else                         rgb = {3{hsp}};
  end

  hdmi_out #(.TRUE_LVDS(1)) out (
      .clk_pixel(clk_pixel), .clk_x5(clk_x5), .reset(reset),
      .red(rgb[23:16]), .green(rgb[15:8]), .blue(rgb[7:0]),
      .hsync_tx(hsync), .vsync_tx(vsync), .active(active),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n));
endmodule
`default_nettype wire
