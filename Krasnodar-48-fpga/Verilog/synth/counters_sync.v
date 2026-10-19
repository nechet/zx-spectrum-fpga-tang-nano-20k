// -----------------------------------------------------------------------------
// Synthesis-only variants of the counters whose real parts are clocked from
// more than one edge -- the '193 counts up on one pin and down on another, and
// the CD4520 counts on either a rising clock or a falling enable.  Neither maps
// to an FPGA flip-flop directly, so each is rewritten onto a single edge.
//
// The '193's two clocks stay as they are because both instances on this board
// tie the down-clock high and only ever count up.  The CD4520's two cases do
// collapse into one edge exactly -- see the note on it below, and note that
// getting this wrong costs the video timing silently.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module ttl_74193 (input p15, p1, p10, p9, p11, p14, p5, p4,
                  output p3, p2, p6, p7, p12, p13,
                  input p8, p16,
                  input clk_sys);             // wired up automatically by bus_resolve.py
  // Both count clocks are board signals (D9 counts on N_55, 7 MHz, and makes
  // the CPU clock from it), so their rising edges are detected on clk_sys
  // rather than used as clocks -- see the note on the '74 below.
  // The previous-value registers power up at 1: where a clock pin is tied high
  // (every CPD here) a 0 would read as a rising edge on the first tick -- the
  // "spurious first decrement" this model once had.
  reg [3:0] q = 4'b0;
  reg up_d = 1'b1, dn_d = 1'b1;
  always @(posedge clk_sys) begin
    up_d <= p5;
    dn_d <= p4;
    if (p14)                q <= 4'b0;
    else if (!p11)          q <= {p9, p10, p1, p15};
    else if (!up_d && p5)   q <= q + 4'd1;
    else if (!dn_d && p4)   q <= q - 4'd1;
  end
  // CLR and /LOAD are asynchronous on the real part: they act on the outputs
  // at once (see the '74 below), and on the stored count at the next clk_sys.
  wire [3:0] qo = p14 ? 4'b0 : !p11 ? {p9, p10, p1, p15} : q;
  assign {p7, p6, p2, p3} = qo;
  assign p12 = ~(&qo    & ~p5);
  assign p13 = ~(~(|qo) & ~p4);
endmodule

// The CD4520 advances on a rising CLOCK while ENABLE is high, *or* on a
// falling ENABLE while CLOCK is low -- which is how D20 is wired on this
// board: its clock pins are tied to ground and the counter is driven from the
// enables.  Both cases are exactly the rising edge of (CLOCK | ~ENABLE).
//
// That edge is then found by sampling on the system clock rather than by
// using it as a clock directly, because on this board it is a combinational
// net and it races.  At the horizontal counter's 0111->1000 step, V3 falls and
// V5 rises together; SSI is NAND(~V3, N$125) and N$125 is a flip-flop that V5
// resets, so the NAND sees the new ~V3 an instant before the flip-flop reacts
// and SSI dips for zero time.  A real CD4520 needs a clock pulse about 100 ns
// wide and ignores the ~20 ns spike the board actually produces; an FPGA
// flip-flop clocked from a LUT output does not, and counts it.  The result is
// a line counter that advances two per line -- 126 lines a frame instead of
// 312, with correct line timing, which is a confusing thing to debug.
//
// Two flops of synchroniser then an edge detect discards anything narrower
// than a system clock period.  The real pulses here are microseconds wide, so
// nothing genuine is lost.
module cd4520 (input p1, p2, p7, p9, p10, p15,
               output p3, p4, p5, p6, p11, p12, p13, p14,
               input p8, p16,
               input clk_sys);
  wire ga = p1 | ~p2;
  wire gb = p9 | ~p10;
  reg [2:0] sa = 3'b0, sb = 3'b0;
  reg [3:0] a = 4'b0, b = 4'b0;
  // Reset has to suppress edge detection for a moment, not just clear the
  // count.  Clearing the low half drops V9, and V9 is the high half's clock on
  // this board, so every reset manufactures one edge on it.  A real CD4520 is
  // already cleared when that happens and never counts it; here the edge would
  // still be working its way through the synchroniser and would land after the
  // one-clock reset pulse had passed, adding 16 to the line count every frame.
  // That gives 296 lines instead of 312 with the horizontal timing perfect,
  // which is a thoroughly misleading symptom.
  //
  // While the hold-off runs, the synchroniser is kept flat at the *current*
  // gate level, so no edge can be seen until the outputs have settled.
  reg [1:0] ha = 2'd0, hb = 2'd0;
  always @(posedge clk_sys) begin
    sa <= {sa[1:0], ga};
    sb <= {sb[1:0], gb};

    if (p7) begin
      a  <= 4'b0;
      sa <= {3{ga}};
      ha <= 2'd2;
    end else if (ha != 2'd0) begin
      sa <= {3{ga}};
      ha <= ha - 2'd1;
    end else if (sa[2:1] == 2'b01)
      a <= a + 4'd1;

    if (p15) begin
      b  <= 4'b0;
      sb <= {3{gb}};
      hb <= 2'd2;
    end else if (hb != 2'd0) begin
      sb <= {3{gb}};
      hb <= hb - 2'd1;
    end else if (sb[2:1] == 2'b01)
      b <= b + 4'd1;
  end

  assign {p6, p5, p4, p3}     = a;
  assign {p14, p13, p12, p11} = b;
endmodule

// The '74's simulation model drives X when preset and clear are asserted at
// once, which has no synthesis meaning.  Here preset simply wins.
//
// Both halves power up at 1 because a Gowin flip-flop's initial value has to
// match its asynchronous set or reset, and the only asynchronous control this
// board actually drives is the preset on D10's second half -- every other
// /PRE and /CLR is tied high.  Starting at 0 makes nextpnr refuse the design
// with "unsupported initial value and async reset value combination".  A real
// 7474 powers up in whichever state it likes, so either value is as faithful.
module ttl_7474 (input p1, p2, p3, p4, p10, p11, p12, p13,
                 output p5, p6, p8, p9,
                 input p7, p14,
                 input clk_sys);              // wired up automatically by bus_resolve.py
  // Clock edges detected on clk_sys, like every other register on this board.
  // As a plain `posedge p3` model, D10 and D8 -- which divide 14 MHz down to
  // the CPU clock -- each became a separate FPGA clock net, and Gowin reported
  // a dozen such derived clocks with no timing relationship to clk_sys; every
  // build failed somewhere different on the Tang Nano 20K.  /PRE and /CLR are
  // asynchronous on the real part and stay so: they gate the outputs at once,
  // and clear the stored state on clk_sys.  (See cd4013 in sync_overrides.v
  // for what a clock-late reset did to the line sync.)
  reg q1 = 1'b1, q2 = 1'b1;
  reg c1_d = 1'b1, c2_d = 1'b1;
  always @(posedge clk_sys) begin
    c1_d <= p3;
    c2_d <= p11;
    if (!p4)                 q1 <= 1'b1;
    else if (!p1)            q1 <= 1'b0;
    else if (!c1_d && p3)    q1 <= p2;
    if (!p10)                q2 <= 1'b1;
    else if (!p13)           q2 <= 1'b0;
    else if (!c2_d && p11)   q2 <= p12;
  end
  wire o1 = !p4  ? 1'b1 : !p1  ? 1'b0 : q1;
  wire o2 = !p10 ? 1'b1 : !p13 ? 1'b0 : q2;
  assign p5 = o1;  assign p6 = ~o1;
  assign p9 = o2;  assign p8 = ~o2;
endmodule

// A NOR fed by a signal and its own inverse is a one-shot.  The two inputs are
// only ever both low for as long as the inverter takes to catch up, so the gate
// emits a pulse one gate-delay wide on the falling edge of the signal.  D50
// uses two of them, and they are not incidental: N$122 resets the horizontal
// counter and N$116 the vertical one, so without them the counters free-run to
// 16 and 256 instead of 28 and 312.
//
// Synthesis has no gate delay to exploit -- ~(X | ~X) folds to a constant 0 --
// so bus_resolve.py replaces the pattern with this: a pulse one system clock
// wide on the same edge.  At 13.5 MHz that is 74 ns, close to what a CD4001
// and a CD4069 in series actually produce at 5 V.
module gate_pulse_sync (input clk_sys, input a, output y);
  reg d = 1'b1;
  reg q = 1'b0;
  always @(posedge clk_sys) begin
    d <= a;
    q <= d & ~a;
  end
  assign y = q;
endmodule
