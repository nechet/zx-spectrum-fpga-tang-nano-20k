// -----------------------------------------------------------------------------
// Behavioural stand-ins for the two rPLLs, for simulation only.
//
// The real pll_14.v and pll_135.v instantiate a Gowin rPLL primitive, which
// Icarus has no model for.  These free-run at the right frequency instead.
// In hardware both are locked to the same 27 MHz crystal as the pixel clock,
// so the frame lock the scan doubler depends on is exact; here they drift by
// the rounding of the half-period to picoseconds, which is about 20 ppm and
// far below anything the timing checks look at.
// -----------------------------------------------------------------------------
`timescale 1ns / 1fs

module pll_14 (input wire clkin, output reg clkout, output wire lock);
  reg locked = 1'b0;
  initial begin
    clkout = 1'b0;
    #50_000 locked = 1'b1;              // 50 us, as a real rPLL takes
  end
  always #35.7142857 clkout = ~clkout;  // 14.000 MHz
  assign lock = locked;
endmodule

module pll_135 (input wire clkin, output reg clkout, output wire lock);
  reg locked = 1'b0;
  initial begin
    clkout = 1'b0;
    #50_000 locked = 1'b1;
  end
  always #3.7037037 clkout = ~clkout;   // 135.00 MHz
  assign lock = locked;
endmodule

// -----------------------------------------------------------------------------
// The serialiser and the differential output buffer are Gowin hard blocks with
// no behavioural model.  These stubs exist only so the design elaborates; the
// TMDS side is genuinely not checkable in simulation -- encoding, 10:1
// serialisation and signal integrity are provable only on a monitor.  What
// simulation *can* check is everything feeding them: the raster, the sync
// polarity, the active window and the pixel data, which is where the mistakes
// have actually been.
// -----------------------------------------------------------------------------
module OSER10 (output wire Q,
               input wire D0, D1, D2, D3, D4, D5, D6, D7, D8, D9,
               input wire PCLK, FCLK, RESET);
  assign Q = 1'b0;
endmodule

module ELVDS_OBUF (input wire I, output wire O, output wire OB);
  assign O  = I;
  assign OB = ~I;
endmodule
