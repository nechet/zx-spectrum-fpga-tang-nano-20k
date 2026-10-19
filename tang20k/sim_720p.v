// -----------------------------------------------------------------------------
// Simulation stand-ins for the 720p build's clocks (pll_405.v, Gowin CLKDIV).
//
// pll_405 free-runs a 405 MHz clock -- its rounding to femtoseconds puts it
// within 30 ppb of the testbench's 27 MHz crystal -- and divides it by 3 for
// the board's 135 MHz, as the rPLL's CLKOUTD3 does.  CLKDIV divides its input
// by DIV_MODE (here 5: 81 MHz).  Both outputs come from the same 405 MHz, so
// the pixel clock and the board clock are locked exactly, as on the chip.
// -----------------------------------------------------------------------------
`timescale 1ns / 1fs

module pll_405 (input wire clkin, output reg clkout, output reg clkout_d3,
                output wire lock);
  reg locked = 1'b0;
  reg [1:0] d3 = 2'd0;
  initial begin
    clkout = 1'b0; clkout_d3 = 1'b0;
    #50_000 locked = 1'b1;              // 50 us, as a real rPLL takes
  end
  always #1.2345679 clkout = ~clkout;   // 405.00 MHz
  always @(posedge clkout) begin
    d3 <= (d3 == 2'd2) ? 2'd0 : d3 + 2'd1;
    clkout_d3 <= (d3 == 2'd0);
  end
  assign lock = locked;
endmodule

module CLKDIV #(parameter DIV_MODE = "2", parameter GSREN = "false")
               (output reg CLKOUT, input wire HCLKIN, input wire RESETN, input wire CALIB);
  localparam N = DIV_MODE == "5" ? 5 : DIV_MODE == "4" ? 4 : DIV_MODE == "8" ? 8 : 2;
  reg [3:0] n = 4'd0;
  initial CLKOUT = 1'b0;
  always @(posedge HCLKIN)
    if (!RESETN) begin n <= 4'd0; CLKOUT <= 1'b0; end
    else begin
      n <= (n == N - 1) ? 4'd0 : n + 4'd1;
      CLKOUT <= (n < N / 2);
    end
endmodule
