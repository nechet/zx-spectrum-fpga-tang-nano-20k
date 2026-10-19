// -----------------------------------------------------------------------------
// Unit test of scan_tripler.v against a synthetic board raster.
//
// Clocks as on the board: one 405 MHz source, /3 for the 135 MHz board-side
// clock (a sample every 10 of its clocks = 13.5 MHz) and /5 for the 81 MHz
// pixel clock, so the two sides are locked exactly, as the PLL makes them.
//
// The source draws 896 x 312 with the board's sync shape: hsync at the start
// of each line, vsync starting mid-line.  Every visible Spectrum pixel p
// (two samples) of line k (counted from the first line after the frame
// pulse) has colour (7k + p) mod 16, so any wrong line, pixel, crop or
// stretch shows up as a mismatch.
//
// Checks: every pixel of an output frame; 1792 clocks a line, 936 lines a
// frame; every realignment after the first finds the counters already where
// it would put them (the lock holds).
// -----------------------------------------------------------------------------
`timescale 1ns / 1fs
`default_nettype none

module tb_tripler;
  localparam H_VIS_START = 159, V_VIS_START = 20, V_CROP = 24;

  // --- clocks ------------------------------------------------------------------
  reg clk405 = 1'b0;
  always #1.2345679 clk405 = ~clk405;
  reg [1:0] d3 = 2'd0;
  reg [2:0] d5 = 3'd0;
  reg clk_in = 1'b0, clk_pixel = 1'b0;
  always @(posedge clk405) begin
    d3 <= (d3 == 2'd2) ? 2'd0 : d3 + 2'd1;
    d5 <= (d5 == 3'd4) ? 3'd0 : d5 + 3'd1;
    clk_in    <= (d3 == 2'd0);
    clk_pixel <= (d5 < 3'd2);
  end

  // --- the board raster ---------------------------------------------------------
  reg [3:0] ced = 4'd0;
  always @(posedge clk_in) ced <= (ced == 4'd9) ? 4'd0 : ced + 4'd1;
  wire ce = (ced == 4'd9);

  reg [9:0] sx = 10'd0;              // sample in line
  reg [8:0] ln = 9'd0;               // line in frame, 0..311
  always @(posedge clk_in) if (ce) begin
    if (sx == 10'd895) begin
      sx <= 10'd0;
      ln <= (ln == 9'd311) ? 9'd0 : ln + 9'd1;
    end else
      sx <= sx + 10'd1;
  end
  // frame pulse from line 309, sample 400, to line 311, sample 400; the first
  // line to start after it rises is 310, which is line k = 0
  wire hs = (sx < 10'd64);
  wire vs = (ln == 9'd309 && sx >= 10'd400) || ln == 9'd310 || (ln == 9'd311 && sx < 10'd400);
  wire [8:0] k = (ln >= 9'd310) ? ln - 9'd310 : ln + 9'd2;   // 310 -> 0
  // the tripler restarts its sample count on the clock it sees hsync, which
  // (both registered below) carries sample 0's pixel: its sample n is our n + 1
  wire [9:0] s = sx - H_VIS_START - 10'd1;
  wire [8:0] p = s[9:1];
  wire [3:0] colour = k * 4'd7 + p[3:0];
  reg  [3:0] rgbi = 4'd0;
  reg        hs_q = 1'b0, vs_q = 1'b0;
  always @(posedge clk_in) if (ce) begin   // registered, as top.v does
    rgbi <= colour; hs_q <= hs; vs_q <= vs;
  end

  wire [10:0] ox;
  wire [9:0]  oy;
  wire hso, vso, act;
  wire [3:0] rgbi_out;
  scan_tripler #(.H_VIS_START(H_VIS_START), .V_VIS_START(V_VIS_START), .V_CROP(V_CROP)) dut (
      .clk_in(clk_in), .ce_in(ce), .rgbi_in(rgbi), .hsync_in(hs_q), .vsync_in(vs_q),
      .clk_pixel(clk_pixel), .ox(ox), .oy(oy), .hsync_out(hso), .vsync_out(vso),
      .active_out(act), .rgbi_out(rgbi_out));

  // --- checks ---------------------------------------------------------------------
  integer fails = 0, frames = 0, realigns = 0;
  integer hlen = 0, vlines = 0, lenerr = 0, frmerr = 0;
  reg hso_d = 1'b0, vso_d = 1'b0;
  always @(posedge clk_pixel) begin
    hso_d <= hso; vso_d <= vso;
    if (hso && !hso_d) begin
      if (frames >= 2 && hlen != 1792) lenerr = lenerr + 1;
      hlen = 1; vlines = vlines + 1;
    end else hlen = hlen + 1;
    if (vso && !vso_d) begin
      if (frames >= 2 && vlines != 936) frmerr = frmerr + 1;
      vlines = 0; frames = frames + 1;
    end
  end

  // the realignment must find the counters already in place
  always @(posedge clk_pixel) if (dut.realign) begin
    realigns = realigns + 1;
    if (realigns > 1 && !(dut.cx == dut.OX_AT_HS - 1 &&
                          dut.cy == dut.V_OUT_TOTAL - dut.V_LEAD - 1 && dut.phase == 2'd2)) begin
      $display("FAIL  realign %0d moved the raster: cx %0d cy %0d phase %0d",
               realigns, dut.cx, dut.cy, dut.phase);
      fails = fails + 1;
    end
  end

  // every active pixel of frames 3 and 4 against the source
  integer bad = 0, checked = 0, v, kk, pp;
  reg [3:0] want;
  always @(posedge clk_pixel) if ((frames == 3 || frames == 4) && act) begin
    v  = oy / 3 + V_CROP;
    kk = v + V_VIS_START - 1;
    pp = (ox < dut.H_PAD) ? 0 : ((ox - dut.H_PAD) / 3 > 351 ? 351 : (ox - dut.H_PAD) / 3);
    want = kk * 7 + pp;
    checked = checked + 1;
    if (rgbi_out !== want) begin
      if (bad < 8) $display("FAIL  pixel (%0d, %0d): %h, want %h (line %0d, pixel %0d)",
                            ox, oy, rgbi_out, want, kk, pp);
      bad = bad + 1;
    end
  end

  initial begin
    wait (frames == 5);
    if (checked != 2 * 1280 * 720) begin
      $display("FAIL  checked %0d pixels, want %0d", checked, 2 * 1280 * 720); fails = fails + 1;
    end else if (bad == 0) $display("PASS  2 frames, every pixel of 1280 x 720 as the source");
    else begin $display("FAIL  %0d pixels wrong", bad); fails = fails + 1; end
    if (lenerr == 0 && frmerr == 0) $display("PASS  1792 clocks a line, 936 lines a frame");
    else begin $display("FAIL  %0d bad lines, %0d bad frames", lenerr, frmerr); fails = fails + 1; end
    if (realigns >= 4 && fails == 0) $display("PASS  %0d realignments, none moved the raster", realigns);
    if (dut.slip_small || dut.slip_big) begin
      $display("FAIL  slip flags set: small %b, big %b", dut.slip_small, dut.slip_big); fails = fails + 1;
    end
    if (fails == 0) $display("ALL PASSED"); else $display("FAILED: %0d", fails);
    $finish;
  end
  initial begin #200_000_000 $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
