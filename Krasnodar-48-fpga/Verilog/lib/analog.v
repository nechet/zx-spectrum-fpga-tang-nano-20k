// -----------------------------------------------------------------------------
// Stand-ins for the parts of the board that are not digital.
//
// These exist because the schematic contains real analogue behaviour that a
// structural Verilog netlist cannot express.  Each one is a deliberate,
// documented approximation -- see Verilog/README.md.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// --- series R with a shunt C: one of the board's timing-correction chains ----
// Approximates the RC as a plain transport delay of 0.7*R*C (the time the node
// needs to cross a logic threshold).  The real network also rounds the edge,
// which matters if the receiving gate has hysteresis; none here do.
module rc_delay #(parameter integer DELAY_PS = 0) (input a, output reg y);
  initial y = 1'b0;
  always @(a) y <= #(DELAY_PS / 1000.0) a;
endmodule

// --- the /INT differentiator: C' (750 pF) + R' (22k) + VD1 clamp -------------
// A falling edge on -KSI (the 50 Hz frame strobe) is coupled through C' and
// pulls /INT low; R' recharges the capacitor, releasing /INT after ~R*C.
// VD1 clamps the positive overshoot and has no logical effect.
module int_pulse #(parameter integer WIDTH_NS = 16500) (input ksi_n, output reg int_n);
  initial int_n = 1'b1;
  always @(negedge ksi_n) begin
    int_n = 1'b0;
    #(WIDTH_NS);
    int_n = 1'b1;
  end
endmodule

// --- the 14 MHz crystal oscillator: ZQ1 + R6 + R7 around two D8 inverters ----
// An inverter-ring oscillator has no meaning in a zero-delay digital
// simulation, so the loop is cut and F14M is driven from here instead.
module clkgen #(parameter integer PERIOD_PS = 71429) (output reg clk);
  initial clk = 1'b0;
  always #(PERIOD_PS / 2000.0) clk = ~clk;
endmodule
