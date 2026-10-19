// -----------------------------------------------------------------------------
// PS/2 receiver: the electrical and protocol layer.
//
// The keyboard drives CLK (10-17 kHz) and DATA; data is valid on CLK's falling
// edge.  A frame is 11 bits: start (0), 8 data bits LSB first, odd parity,
// stop (1).  Out comes one byte -- a scancode or prefix -- with a one-cycle
// `valid` pulse.  Knows nothing about keyboards or Spectrums.
//
// Both pins are asynchronous to clk_sys, so they pass a two-flop synchroniser
// before any logic sees them (see LEARNING.md, 7.10), and CLK is glitch
// filtered.  Receive only: nothing is ever sent to the keyboard.
// -----------------------------------------------------------------------------
`default_nettype none

module ps2_rx (
    input  wire       clk,          // clk_sys, 135 MHz
    input  wire       ps2_clk,      // from the pin, asynchronous
    input  wire       ps2_data,
    output reg  [7:0] code = 8'h00,
    output reg        valid = 1'b0, // one clk cycle per received byte
    output reg        err = 1'b0,   // one clk cycle per rejected frame (debug)
    output wire       clk_low,      // CLK line, filtered: 1 = low (debug)
    output wire       data_low,     // DATA line, synchronised: 1 = low (debug)
    output wire       clk_fall      // one clk cycle per CLK falling edge (debug)
);
  // Two-flop synchroniser, then a glitch filter: a level only counts once it
  // has been stable for 128 clk_sys (~1 us).  PS/2 clock half-periods are
  // 30-50 us, so nothing real is lost, and ringing on a long cable is.
  reg [1:0] c_s = 2'b11, d_s = 2'b11;
  reg [6:0] c_cnt = 7'd0;
  reg       c_f = 1'b1, c_fd = 1'b1;
  always @(posedge clk) begin
    c_s <= {c_s[0], ps2_clk};
    d_s <= {d_s[0], ps2_data};
    if (c_s[1] == c_f)       c_cnt <= 7'd0;
    else if (&c_cnt)         begin c_f <= c_s[1]; c_cnt <= 7'd0; end
    else                     c_cnt <= c_cnt + 7'd1;
    c_fd <= c_f;
  end
  wire fall = c_fd & ~c_f;          // the keyboard's data is valid on CLK falling
  assign clk_low  = ~c_f;
  assign data_low = ~d_s[1];
  assign clk_fall = fall;

  // Frame: start (0), 8 data bits LSB first, odd parity, stop (1).  If the
  // clock stops for ~2 ms mid-frame (a glitch, a plugged-in keyboard), start
  // over, so one bad bit cannot shift every later byte.
  reg [3:0]  nbit = 4'd0;
  reg [9:0]  sh   = 10'd0;
  reg [18:0] idle = 19'd0;
  always @(posedge clk) begin
    valid <= 1'b0;
    err   <= 1'b0;
    if (fall) begin
      idle <= 19'd0;
      if (nbit == 4'd0) begin
        if (!d_s[1]) nbit <= 4'd1;           // start bit
      end else begin
        sh <= {d_s[1], sh[9:1]};
        if (nbit == 4'd10) begin             // that was the stop bit
          nbit <= 4'd0;
          // Before this last shift lands, sh[9] is the parity bit and
          // sh[8:1] the data, d7..d0; d_s[1] is the stop bit just sampled.
          // Odd parity: data and parity together have an odd number of 1s.
          if (d_s[1] && (^sh[9:1] == 1'b1)) begin
            code  <= sh[8:1];
            valid <= 1'b1;
          end else
            err   <= 1'b1;
        end else
          nbit <= nbit + 4'd1;
      end
    end else if (nbit != 4'd0) begin
      if (&idle) nbit <= 4'd0;
      else       idle <= idle + 19'd1;
    end
  end
endmodule
`default_nettype wire
