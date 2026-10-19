// -----------------------------------------------------------------------------
// Synthesisable replacements for the two simulation-only helpers in lib/analog.v.
// Used by krasnodar48_synth.v (the --synth output of the generator).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// The RC timing-correction chains exist to shift an edge by a few nanoseconds
// against gate propagation delay.  In an FPGA there is no delay to correct, so
// the baseline is a straight connection.  If a design needs the delay back,
// replace this with a shift register clocked well above 14 MHz.
// An RC delay line, as a shift register on a fast clock.
//
// These are NOT trimming out gate propagation delay, which is what an earlier
// version of this file assumed when it made them plain wires.  They are the
// board's DRAM timing generator: R8 and R9 stagger /CAS behind /RAS, and R11
// delays the row/column multiplexer select that has to change in between.
// With them shorted out, /RAS, /CAS and /WE all fall in the same instant and
// the address never leaves its row phase -- the memory sees one impossible
// cycle per access and stores nothing useful.
//
// clk_sys has to be fast enough to resolve them: the delays here are 7.9 ns
// and 20.2 ns, so at 135 MHz (7.4 ns a tick) they come out as 1 and 3 ticks.
// bus_resolve.py wires clk_sys automatically.
module rc_delay_sync #(parameter integer DELAY_PS = 0,
                       parameter integer CLK_PS   = 7407)   // 135 MHz
                      (input a, output y, input clk_sys);
  localparam integer STAGES = (DELAY_PS + CLK_PS / 2) / CLK_PS;
  generate
    if (STAGES <= 0) begin : none
      assign y = a;
    end else begin : delayed
      reg [STAGES:0] sr = {(STAGES + 1){1'b1}};
      always @(posedge clk_sys) sr <= {sr[STAGES-1:0], a};
      assign y = sr[STAGES];
    end
  endgenerate
endmodule

// The C'/R' differentiator that turns the falling edge of the frame strobe into
// an /INT pulse, as a synchronous one-shot of ~16.5 us.  Counted on clk_sys
// (135 MHz, 2227 cycles) rather than on the 14 MHz board clock, so it is in
// the same clock domain as everything else; `clk` is kept so the netlist
// instance does not change, and is unused.
module int_pulse_sync #(parameter integer WIDTH_NS = 16500,
                        parameter integer SYS_MHZ  = 135)
                      (input clk, input ksi_n, output int_n,
                       input clk_sys);        // wired up automatically by bus_resolve.py
  localparam integer CYCLES = (WIDTH_NS * SYS_MHZ) / 1000;
  reg [11:0] cnt = 12'd0;
  reg ksi_d = 1'b1;
  always @(posedge clk_sys) begin
    ksi_d <= ksi_n;
    if (ksi_d && !ksi_n)      cnt <= CYCLES[11:0];
    else if (cnt != 12'd0)    cnt <= cnt - 12'd1;
  end
  assign int_n = (cnt == 12'd0);
endmodule
