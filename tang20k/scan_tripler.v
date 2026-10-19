// -----------------------------------------------------------------------------
// Line tripler: the board's 896 x 312 raster into 1280 x 720 (16:9) HDMI.
//
// Each Spectrum pixel becomes 3 x 3 screen pixels.  The output raster is
// 1792 x 936 at 81 MHz, and the board's master clock is 13.5 MHz, from the
// same PLL: 81 is exactly 6 x 13.5, so one input line (896 board clocks) is
// exactly three output lines (3 x 1792 pixel clocks), and a frame is exactly
// a frame (936 = 3 x 312).  Nothing drifts, so nothing tears -- the same
// trick as scan_doubler.v, with three lines per input line instead of two.
//
// What is shown, in Spectrum pixels:
//   vertically    240 of the 288 visible lines: 24 border lines above the
//                 paper and 24 below (720 / 3 = 240), instead of 48
//   horizontally  all 352 the board's window holds = 1056 screen pixels,
//                 placed so the paper is centred.  The window is not: its
//                 paper starts at pixel 64 (64 border pixels on the left, 32
//                 on the right -- seen in tb_720p's frame).  The 64 screen
//                 pixels left of it and the 160 right of it repeat the line's
//                 first and last pixel -- the border colour, so the border
//                 reaches the edges of the 16:9 screen and loading stripes
//                 run the full width
//
// Two line buffers ping-pong, as in the doubler: one is written at the board
// pixel rate while the other is read three times at 81 MHz.  They are also
// the clock-domain crossing.  Only every second sample is kept (the board is
// sampled twice per Spectrum pixel), so a line is 352 entries.
//
// The input line starts (and the buffers swap) in the horizontal blanking of
// the third output line, OX_AT_HS pixels into it.  The read side picks its
// buffer at the start of each triple, ~190 pixel clocks later, long after the
// swap has crossed the two-flop synchroniser -- no line ever starts on a
// half-swapped buffer.  OX_AT_HS is past the HDMI data islands (which follow
// the active pixels), so even a realignment never lands inside one.
//
// Timing: ox, oy, the syncs, active_out and rgbi_out all describe the same
// pixel in the same clock (the buffer's read latency is taken up inside).
// -----------------------------------------------------------------------------
`default_nettype none

module scan_tripler #(
    parameter H_IN_TOTAL   = 896,   // input samples per line
    parameter H_VIS_START  = 159,   // first visible input sample after hsync
    parameter V_VIS_START  = 20,    // first visible input line after vsync
    parameter V_CROP       = 24,    // visible lines not shown, top (and bottom)
    parameter SAMPLE_PHASE = 1,     // which of the two samples per pixel to keep
    parameter PAPER_X      = 64,    // Spectrum pixel of the window where the paper starts
    parameter H_OUT_ACTIVE = 1280,
    parameter H_OUT_FRONT  = 110,
    parameter H_OUT_SYNC   = 40,
    parameter H_OUT_TOTAL  = 1792,  // 6 x 896 / 3
    parameter V_OUT_ACTIVE = 720,
    parameter V_OUT_FRONT  = 5,
    parameter V_OUT_SYNC   = 5,
    parameter V_OUT_TOTAL  = 936,   // 3 x 312
    parameter OX_AT_HS     = 1600   // where in an output line the input line starts
) (
    // --- input side, board clock domain --------------------------------------
    input  wire        clk_in,
    input  wire        ce_in,       // one sample per board pixel clock
    input  wire [3:0]  rgbi_in,     // {bright, red, green, blue}
    input  wire        hsync_in,    // 1 during the pulse
    input  wire        vsync_in,

    // --- output side, 81 MHz pixel clock -------------------------------------
    input  wire        clk_pixel,
    output reg  [10:0] ox = 11'd0,
    output reg  [9:0]  oy = 10'd0,
    output reg         hsync_out = 1'b0,
    output reg         vsync_out = 1'b0,
    output reg         active_out = 1'b0,
    output wire [3:0]  rgbi_out,
    // diagnostics, sticky: the realignment found the raster a pixel or two
    // off (and left it), or further off than that after the first lock
    output reg         slip_small = 1'b0,
    output reg         slip_big = 1'b0);

  localparam PIX     = 352;                              // Spectrum pixels a line
  localparam H_PAD   = H_OUT_ACTIVE / 2 - 3 * (PAPER_X + 128);   // 64: the paper centred
  localparam V_LEAD  = 3 * (V_VIS_START + V_CROP);       // see the realignment

  // ---------------------------------------------------------------- write side
  reg [9:0] wx   = 10'd0;           // input sample counter
  reg       wbuf = 1'b0;            // buffer being written
  reg       hs_d = 1'b0;
  reg [3:0] linebuf [0:1023];       // 2 x 512 x 4 bits -> one BSRAM
  integer   k;
  initial for (k = 0; k < 1024; k = k + 1) linebuf[k] = 4'd0;

  wire [9:0] waddr  = wx - H_VIS_START;
  wire       in_vis = (wx >= H_VIS_START) && (wx < H_VIS_START + 2 * PIX);

  always @(posedge clk_in) if (ce_in) begin
    hs_d <= hsync_in;
    if (hsync_in && !hs_d) begin    // start of an input line
      wx   <= 10'd0;
      wbuf <= ~wbuf;
    end else if (wx != H_IN_TOTAL - 1)
      wx <= wx + 10'd1;

    if (in_vis && waddr[0] == SAMPLE_PHASE)
      linebuf[{wbuf, waddr[9:1]}] <= rgbi_in;
  end

  // ----------------------------------------------------------- sync crossing
  // Realign once per frame, on the first input line after the frame pulse (as
  // the doubler does, and for the same reason) -- but only if the raster is
  // really out of place.  With the clocks locked it is already where the
  // realignment would put it, give or take the synchroniser: the line sync
  // crosses from 135 to 81 MHz, and should its edge land at the sampling
  // instant it can be seen a clock early or late.  Moving the raster by that
  // pixel each frame is a glitch the monitor's sound decoder need not forgive,
  // so a pixel or two either way is left alone.
  reg vs_m = 1'b0, vs_s = 1'b0, vs_d = 1'b0;
  reg hs_m = 1'b0, hs_s = 1'b0, hsp_d = 1'b0;
  reg armed = 1'b0;
  reg wbuf_m = 1'b0, wbuf_s = 1'b0;
  always @(posedge clk_pixel) begin
    vs_m <= vsync_in; vs_s <= vs_m; vs_d <= vs_s;
    hs_m <= hsync_in; hs_s <= hs_m; hsp_d <= hs_s;
    wbuf_m <= wbuf;   wbuf_s <= wbuf_m;
    if (vs_s && !vs_d)                armed <= 1'b1;
    else if (armed && hs_s && !hsp_d) armed <= 1'b0;
  end
  wire realign = armed && hs_s && !hsp_d;

  // ---------------------------------------------------------- output raster
  // cx, cy run one clock ahead of ox, oy: the buffer read takes that clock.
  //
  // Which output line the realignment lands in: the triple after input line
  // boundary k shows the line written before it, k - 1.  The doubler's
  // window makes visible line 0 the one before boundary V_VIS_START, so the
  // first line shown (visible line V_CROP) follows boundary V_VIS_START +
  // V_CROP, and output line 0 must start V_LEAD lines after boundary 0.
  reg [10:0] cx = 11'd0;
  reg [9:0]  cy = 10'd0;
  reg [1:0]  phase = 2'd0;          // output line within its triple
  reg        rbuf = 1'b0;           // buffer being read
  // where the counters would be on the next clock, against the realignment's
  // target: in lock if the line, the triple and the pixel within two agree
  wire [10:0] cx_next = cx + 11'd1;
  wire in_lock  = (cy == V_OUT_TOTAL - V_LEAD - 1) && (phase == 2'd2) &&
                  (cx_next + 11'd2 >= OX_AT_HS) && (cx_next <= OX_AT_HS + 2);
  wire do_align = realign && !in_lock;
  reg  locked   = 1'b0;
  always @(posedge clk_pixel) if (realign) begin
    locked <= 1'b1;
    if (in_lock && cx_next != OX_AT_HS) slip_small <= 1'b1;
    if (!in_lock && locked)             slip_big   <= 1'b1;
  end

  always @(posedge clk_pixel) begin
    if (do_align) begin
      cx    <= OX_AT_HS;
      cy    <= V_OUT_TOTAL - V_LEAD - 1;
      phase <= 2'd2;
    end else if (cx == H_OUT_TOTAL - 1) begin
      cx    <= 11'd0;
      cy    <= (cy == V_OUT_TOTAL - 1) ? 10'd0 : cy + 10'd1;
      phase <= (phase == 2'd2) ? 2'd0 : phase + 2'd1;
      if (phase == 2'd2) rbuf <= ~wbuf_s;
    end else
      cx <= cx + 11'd1;
  end

  // Read address: Spectrum pixel rx, held for three output pixels from H_PAD
  // on; before that it rests on pixel 0 and after it on pixel 351, so the
  // sides repeat the border at each end of the line.  (Pixel 0 also covers
  // H_PAD's first three pixels: the address moves on the clock after.)
  reg [8:0] rx  = 9'd0;
  reg [1:0] sub = 2'd0;
  always @(posedge clk_pixel)
    if (cx == H_OUT_TOTAL - 1 || do_align) begin
      rx <= 9'd0; sub <= 2'd0;
    end else if (cx >= H_PAD && cx < H_PAD + 3 * PIX) begin
      if (sub == 2'd2) begin
        sub <= 2'd0;
        if (rx != PIX - 1) rx <= rx + 9'd1;
      end else
        sub <= sub + 2'd1;
    end

  reg [3:0] rgbi_q = 4'd0;
  always @(posedge clk_pixel) begin
    rgbi_q     <= linebuf[{rbuf, rx}];
    ox         <= cx;
    oy         <= cy;
    hsync_out  <= (cx >= H_OUT_ACTIVE + H_OUT_FRONT) &&
                  (cx <  H_OUT_ACTIVE + H_OUT_FRONT + H_OUT_SYNC);
    vsync_out  <= (cy >= V_OUT_ACTIVE + V_OUT_FRONT) &&
                  (cy <  V_OUT_ACTIVE + V_OUT_FRONT + V_OUT_SYNC);
    active_out <= (cx < H_OUT_ACTIVE) && (cy < V_OUT_ACTIVE);
  end

  assign rgbi_out = active_out ? rgbi_q : 4'd0;
endmodule
`default_nettype wire
