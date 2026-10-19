// -----------------------------------------------------------------------------
// The Spectrum's beeper as 48 kHz, 16-bit audio samples for HDMI.
//
// The beeper is one bit: the CPU toggles it, and on the real machine a
// transistor drives the speaker through a coupling capacitor.  This does the
// same job digitally, in three stages:
//
//   1. clk_audio, 48 kHz from 27 MHz.  27e6 / 48e3 = 562.5, so a counter
//      steps by 2 and wraps at 1125: periods alternate 562 and 563 clocks
//      and average exactly 48 kHz -- a fractional divider.  On a faster
//      pixel clock (81 MHz for 720p) CLK_DIV divides it down to 27 MHz first:
//      everything below then runs on that clock enable, unchanged.
//   2. An integrator: over each sample period, add +AMP for every clock the
//      speaker bit is high and -AMP when low (the tape output adds a quarter
//      of that).  That is the RC low-pass in front of an ADC: it averages
//      the bit, so fast toggling becomes an in-between level, not aliasing.
//   3. A coupling capacitor (a one-pole high-pass, y = x - x' + y - y/256):
//      the speaker bit rests high or low, and that DC level would otherwise
//      sit in the output as an offset.
//
// A new sample is taken at each period's end, when clk_audio falls, so it
// is stable half a period before the rising edge that packet_picker samples
// on: change data on one edge, clock it on the other.
// -----------------------------------------------------------------------------
`default_nettype none

module beeper_audio #(
    parameter CLK_DIV = 1                   // clk_pixel / 27 MHz: 1 (576p), 3 (720p)
) (
    input  wire        clk_pixel,           // CLK_DIV x 27 MHz
    input  wire        speaker,             // the beeper bit, any clock domain
    input  wire        tape,                // the tape (MIC) output, ditto
    output reg         clk_audio = 1'b0,    // 48 kHz
    output reg  [15:0] sample = 16'd0);     // signed, both channels

  // two-flop synchronisers: the board's signals change on its own clock
  reg [1:0] spk_s = 2'b00, tap_s = 2'b00;
  always @(posedge clk_pixel) begin
    spk_s <= {spk_s[0], speaker};
    tap_s <= {tap_s[0], tape};
  end

  // the 27 MHz clock enable
  reg [1:0] div = 2'd0;
  wire ce = (div == CLK_DIV - 1);
  always @(posedge clk_pixel) div <= ce ? 2'd0 : div + 2'd1;

  // 1. the fractional divider: acc steps 0, 2, 4 .. and wraps at 1125
  reg  [10:0] acc = 11'd0;
  wire [11:0] acc_up = acc + 11'd2;
  wire        wrap   = acc_up >= 12'd1125;
  wire [11:0] acc_wr = acc_up - 12'd1125;       // < 2 after a wrap: fits 11 bits
  always @(posedge clk_pixel) if (ce) begin
    acc       <= wrap ? acc_wr[10:0] : acc_up[10:0];
    clk_audio <= !wrap && acc_up >= 12'd563;    // low for the first half of a period
  end

  // 2. the integrator: up to 563 x (16 + 4) = 11260 either way
  localparam signed [15:0] AMP = 16, AMP_TAPE = 4;
  reg signed [15:0] sum = 16'sd0;
  wire signed [15:0] step = (spk_s[1] ? AMP : -AMP) + (tap_s[1] ? AMP_TAPE : -AMP_TAPE);

  // 3. the high-pass, with headroom: a step from -11260 to +11260 overshoots
  // to about twice that before it decays
  reg signed [17:0] x_prev = 18'sd0, y = 18'sd0;
  wire signed [17:0] x = sum + step;               // this period's average, scaled
  wire signed [17:0] y_next = x - x_prev + y - (y >>> 8);

  always @(posedge clk_pixel)
    if (ce && wrap) begin
      sum    <= 16'sd0;
      x_prev <= x;
      y      <= y_next;
      sample <= y_next > 18'sd32767 ? 16'h7FFF :
                y_next < -18'sd32768 ? 16'h8000 : y_next[15:0];
    end else if (ce)
      sum <= sum + step;
endmodule
`default_nettype wire
