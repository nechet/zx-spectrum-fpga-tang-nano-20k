// -----------------------------------------------------------------------------
// Line doubler: ZX Spectrum video (15.625 kHz, 312 lines, 50.08 Hz) into a
// 31.25 kHz / 624-line raster a monitor will accept over HDMI.
//
// Every input line is shown twice, so 312 lines become 624 and the frame rate
// is untouched.  The output raster is 864 x 624 at 27 MHz = 19.968 ms, which is
// exactly one Spectrum frame -- provided the input pixel clock comes from the
// same crystal, so that one input line is exactly two output lines (64 us).
// Nothing drifts, so nothing ever tears.
//
// Horizontally the visible part of the input line is resampled onto the 720
// active output pixels with a Bresenham accumulator, about 1.875x.
//
// Two line buffers ping-pong: one is written at the input pixel rate while the
// other is read twice at the output rate.  They are also the clock-domain
// crossing between the video source's pixel clock and the 27 MHz one.
// -----------------------------------------------------------------------------
`default_nettype none

module scan_doubler #(
    parameter H_IN_TOTAL   = 896,   // input samples per line (14 MHz x 64 us)
    parameter H_VIS_START  = 159,   // first visible input sample after hsync
    parameter H_VIS_LEN    = 704,   // visible input samples: border + display
    parameter V_VIS_START  = 20,    // first visible input line after vsync
    parameter H_OUT_ACTIVE = 720,
    parameter H_OUT_FRONT  = 16,
    parameter H_OUT_SYNC   = 64,
    parameter H_OUT_TOTAL  = 896,
    parameter V_OUT_ACTIVE = 576,
    parameter V_OUT_FRONT  = 3,
    parameter V_OUT_SYNC   = 5,
    parameter V_OUT_TOTAL  = 624    // 2 x 312, NOT the 625 of stock 576p50
) (
    // --- input side, board pixel clock ---------------------------------------
    input  wire       clk_in,
    input  wire       ce_in,        // one sample per board pixel clock
    input  wire [3:0] rgbi_in,      // {bright, red, green, blue}
    input  wire       hsync_in,     // 1 during the pulse
    input  wire       vsync_in,

    // --- output side, 27 MHz pixel clock -------------------------------------
    input  wire       clk_pixel,
    output reg  [9:0] ox,
    output reg  [9:0] oy,
    output wire       hsync_out,
    output wire       vsync_out,
    output wire       active_out,
    output wire [3:0] rgbi_out);

  // ---------------------------------------------------------------- write side
  // The board is sampled at its own 14 MHz, which is two samples per Spectrum
  // pixel, so a line needs 1024 entries a side rather than 512.  Two of those
  // is 8 Kbit, still one 18 Kbit BSRAM.
  reg [9:0] wx    = 10'd0;          // input sample counter
  reg       wbuf  = 1'b0;           // buffer being written
  reg       hs_d  = 1'b0;
  reg [3:0] linebuf [0:2047];       // 2 x 1024 x 4 bits -> one BSRAM
  integer   k;
  initial for (k = 0; k < 2048; k = k + 1) linebuf[k] = 4'd0;

  wire in_visible = (wx >= H_VIS_START) && (wx < H_VIS_START + H_VIS_LEN);
  wire [9:0] waddr = wx - H_VIS_START;

  // clk_in may be faster than the board's pixel rate (it is clk_sys on the
  // fully synchronous build); ce_in marks the one cycle per board pixel to
  // sample on.  With clk_in at the pixel rate, tie ce_in high.
  always @(posedge clk_in) if (ce_in) begin
    hs_d <= hsync_in;
    if (hsync_in && !hs_d) begin    // start of an input line
      wx   <= 10'd0;
      wbuf <= ~wbuf;
    end else if (wx != H_IN_TOTAL - 1)
      wx <= wx + 10'd1;

    if (in_visible)
      linebuf[{wbuf, waddr}] <= rgbi_in;
  end

  // ----------------------------------------------------------- sync crossing
  // The output raster free-runs and is realigned once per frame.  One input
  // line is exactly two output lines (896 clocks of 14 MHz is 1728 of 27, and
  // both come from the same crystal), so nothing drifts in between.
  //
  // The realignment waits for the first input *line* after the frame pulse
  // rather than acting on the frame pulse itself.  The frame sync falls
  // somewhere in the middle of a line, and starting the output raster there
  // would offset the whole picture horizontally by however far into the line
  // that happened to be.
  reg vs_m = 1'b0, vs_s = 1'b0, vs_d = 1'b0;
  reg hs_m = 1'b0, hs_s = 1'b0, hsp_d = 1'b0;
  reg armed = 1'b0;
  always @(posedge clk_pixel) begin
    vs_m <= vsync_in; vs_s <= vs_m; vs_d <= vs_s;
    hs_m <= hsync_in; hs_s <= hs_m; hsp_d <= hs_s;
    if (vs_s && !vs_d)                armed <= 1'b1;
    else if (armed && hs_s && !hsp_d) armed <= 1'b0;
  end
  wire vsync_edge = armed && hs_s && !hsp_d;

  // Output lines from that realignment to the first visible one.  The input
  // has V_VIS_START blanked lines to get through and each is two output lines.
  localparam V_LEAD = 2 * V_VIS_START;

  reg wbuf_m = 1'b0, wbuf_s = 1'b0;
  always @(posedge clk_pixel) begin
    wbuf_m <= wbuf; wbuf_s <= wbuf_m;
  end

  // ---------------------------------------------------------------- read side
  initial begin ox = 10'd0; oy = 10'd0; end

  always @(posedge clk_pixel) begin
    if (vsync_edge) begin
      // Start the raster V_LEAD output lines before active video, so oy
      // reaches 0 exactly as the first visible input line arrives.
      ox <= 10'd0;
      oy <= V_OUT_TOTAL - V_LEAD;
    end else if (ox == H_OUT_TOTAL - 1) begin
      ox <= 10'd0;
      oy <= (oy == V_OUT_TOTAL - 1) ? 10'd0 : oy + 10'd1;
    end else
      ox <= ox + 10'd1;
  end

  assign hsync_out  = (ox >= H_OUT_ACTIVE + H_OUT_FRONT) &&
                      (ox <  H_OUT_ACTIVE + H_OUT_FRONT + H_OUT_SYNC);
  assign vsync_out  = (oy >= V_OUT_ACTIVE + V_OUT_FRONT) &&
                      (oy <  V_OUT_ACTIVE + V_OUT_FRONT + V_OUT_SYNC);
  assign active_out = (ox < H_OUT_ACTIVE) && (oy < V_OUT_ACTIVE);

  // horizontal resample: advance the read address H_VIS_LEN times per
  // H_OUT_ACTIVE output pixels
  reg [10:0] acc = 11'd0;
  reg [9:0]  rx  = 10'd0;
  always @(posedge clk_pixel) begin
    if (ox == H_OUT_TOTAL - 1) begin        // next output line starts
      acc <= 11'd0;
      rx  <= 10'd0;
    end else if (ox < H_OUT_ACTIVE) begin
      if (acc + H_VIS_LEN >= H_OUT_ACTIVE) begin
        acc <= acc + H_VIS_LEN - H_OUT_ACTIVE;
        rx  <= rx + 10'd1;
      end else
        acc <= acc + H_VIS_LEN;
    end
  end

  // read the buffer that is not currently being written
  reg [3:0] rgbi_q = 4'd0;
  always @(posedge clk_pixel)
    rgbi_q <= linebuf[{~wbuf_s, rx}];

  assign rgbi_out = active_out ? rgbi_q : 4'd0;
endmodule
`default_nettype wire
