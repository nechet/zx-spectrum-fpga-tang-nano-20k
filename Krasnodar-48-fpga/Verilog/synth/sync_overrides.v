// Synchronous replacements for parts of lib/ttl.v, used only in the FPGA
// build.  mk_synth_lib.py drops the lib/ttl.v definitions of these modules
// and appends this file to lib_sync.v, so regenerating lib_sync.v (which
// happens whenever lib/ttl.v changes) can no longer silently lose them.
//
// Each one replaces a capture on a board-generated strobe edge -- a race on
// real TTL won by a gate delay, lost on an FPGA -- with an edge detect on
// clk_sys.  bus_resolve.py wires the clk_sys port up automatically.

module ttl_74253 (input p14, p2, p1, p6, p5, p4, p3, p15, p10, p11, p12, p13,
                  output p7, p9,
                  input p8, p16,
                  input clk_sys);             // wired up automatically by bus_resolve.py
  // On this board the four '253s are the DRAM address multiplexers, and their
  // low select (p14) is /RAS itself: high presents the row, low the column.
  // Real DRAM latches the row as /RAS falls, and it is the multiplexer's own
  // propagation delay that keeps the row on the pins long enough.  The data
  // inputs, meanwhile, are counter bits that may change on the very tick that
  // makes /RAS fall -- and in hardware they settle *before* /RAS arrives,
  // which comes out of three more gates.
  //
  // So: data inputs pass straight through, but the select takes effect one
  // system clock late.  When the DRAM model sees /RAS fall it then reads the
  // row with every counter bit already updated, and only afterwards does the
  // multiplexer switch to the column for /CAS.  Without this the model took
  // the column as the row (54 distinct video addresses a frame); sampling one
  // clock early instead took stale counter bits (68 rows of 128).
  reg [1:0] sel = 2'b00;
  always @(posedge clk_sys) sel <= {p2, p14};
  wire d1 = (sel == 2'd0) ? p6 : (sel == 2'd1) ? p5 : (sel == 2'd2) ? p4 : p3;
  wire d2 = (sel == 2'd0) ? p10 : (sel == 2'd1) ? p11 : (sel == 2'd2) ? p12 : p13;
  assign p7 = p1  ? 1'bz : d1;
  assign p9 = p15 ? 1'bz : d2;
endmodule

module ttl_74175 (input p1, p4, p5, p9, p12, p13,
                  output p2, p3, p6, p7, p10, p11, p14, p15,
                  input p8, p16,
                  input clk_sys);             // wired up automatically by bus_resolve.py
  // Quad D flip-flop, rising edge of p9, /CLR on p1.  On this board it is the
  // attribute latch, clocked by VDC (N_108 through an RC delay) and taking the
  // DRAM data bus.  Clocked directly by VDC it was a separately routed clock
  // with its own skew against the bus: fine in simulation, wrong attributes on
  // the Tang Nano 20K (black paper, blue ink where the test ROM writes 0x38).
  // So detect the edge on clk_sys and capture there, which behaves the same in
  // simulation and on the FPGA.
  reg [3:0] q = 4'b0;
  reg ck_d = 1'b0;
  always @(posedge clk_sys) begin
    ck_d <= p9;
    if (!p1)               q <= 4'b0;
    else if (!ck_d && p9)  q <= {p13, p12, p5, p4};
  end
  assign {p2, p3}   = { q[0], ~q[0]};
  assign {p7, p6}   = { q[1], ~q[1]};
  assign {p10, p11} = { q[2], ~q[2]};
  assign {p15, p14} = { q[3], ~q[3]};
endmodule

module ttl_74295 (input p1, p2, p3, p4, p5, p6, p8, p9,
                  output p13, p12, p11, p10,
                  input p7, p14,
                  input clk_sys);             // wired up automatically by bus_resolve.py
  // 4-bit shift register, falling edge of p9; p6 high = parallel load.  On
  // this board these are the pixel shifters, clocked by VCLK and F3_5M --
  // board-generated signals that, used as FPGA clocks, are routed with their
  // own skew against the data they take.  Edge detected on clk_sys instead,
  // so simulation and hardware agree cycle for cycle.
  reg [3:0] q = 4'b0;
  reg ck_d = 1'b0;
  always @(posedge clk_sys) begin
    ck_d <= p9;
    if (ck_d && !p9) begin
      if (p6) q <= {p5, p4, p3, p2};        // parallel load  (QA..QD <= A..D)
      else    q <= {q[2:0], p1};            // shift right    (SER -> QA)
    end
  end
  assign p13 = p8 ? q[0] : 1'b1;   // QA
  assign p12 = p8 ? q[1] : 1'b1;   // QB
  assign p11 = p8 ? q[2] : 1'b1;   // QC
  assign p10 = p8 ? q[3] : 1'b1;   // QD
endmodule

module ttl_74298 (input p1, p2, p3, p4, p5, p6, p7, p9, p10, p11,
                  output p12, p13, p14, p15,
                  input p8, p16,
                  input clk_sys);             // wired up automatically by bus_resolve.py
  // A '298 stores on the HIGH-to-LOW edge of its clock (p11), taking port 2
  // when the select (p10) is high.  On this board the clock is WR and the
  // select is WR6 = ~(/IORQ | A0): both end together at the close of an OUT,
  // so on real TTL the select and the data survive the edge only by a gate
  // delay.  On an FPGA that race goes whichever way the routing falls -- the
  // Tang Nano 20K came up with a blue border (001) where the ROM writes white
  // (111).  So track select and both ports on the system clock while the
  // strobe is still high, and on its falling edge commit the last values seen
  // before it fell.
  reg [3:0] q    = 4'b0;                      // {Q4, Q3, Q2, Q1}
  reg [3:0] d1_r = 4'b0, d2_r = 4'b0;
  reg       sel_r = 1'b0, ck_d = 1'b0;
  always @(posedge clk_sys) begin
    ck_d <= p11;
    if (p11) begin
      sel_r <= p10;
      d2_r  <= {p6, p5, p1, p2};              // port 2: D2 C2 B2 A2
      d1_r  <= {p7, p9, p4, p3};              // port 1: D1 C1 B1 A1
    end
    if (ck_d && !p11) q <= sel_r ? d2_r : d1_r;
  end
  assign {p12, p13, p14, p15} = q;
endmodule

module cd4013 (input p3, p4, p5, p6, p8, p9, p10, p11,
               output p1, p2, p12, p13,
               input p7, p14,
               input clk_sys);                // wired up automatically by bus_resolve.py
  // Dual D flip-flop: rising clock (3, 11), active-high reset (4, 10) and set
  // (6, 8).  Clock edges are detected on clk_sys; reset and set are
  // asynchronous on the real part and stay so here, as gating on the outputs
  // (and they clear the stored state on clk_sys).  Applying them a clock late
  // instead let D34's reset, V5, arrive 7 ns after V3 -- which changes on the
  // same counter tick -- and SSI = NAND(~V3, Q) glitched low for that 7 ns:
  // two line syncs per line, and the scan doubler never locked.
  reg q1 = 1'b0, q2 = 1'b0;
  reg c1_d = 1'b1, c2_d = 1'b1;
  always @(posedge clk_sys) begin
    c1_d <= p3;
    c2_d <= p11;
    if (p4)                  q1 <= 1'b0;
    else if (p6)             q1 <= 1'b1;
    else if (!c1_d && p3)    q1 <= p5;
    if (p10)                 q2 <= 1'b0;
    else if (p8)             q2 <= 1'b1;
    else if (!c2_d && p11)   q2 <= p9;
  end
  wire o1 = p4  ? 1'b0 : p6 ? 1'b1 : q1;
  wire o2 = p10 ? 1'b0 : p8 ? 1'b1 : q2;
  assign p1  =  o1;
  assign p2  = ~o1;
  assign p13 =  o2;
  assign p12 = ~o2;
endmodule

module cd4015 #(parameter integer TPLH = 40,  // clk_sys ticks: rising outputs, ~300 ns
                parameter integer TPHL = 33)  // falling outputs, ~245 ns
              (input p1, p7, p6, p9, p15, p14,
               output p5, p4, p3, p2, p13, p12, p11, p10,
               input p8, p16,
               input clk_sys);                // wired up automatically by bus_resolve.py
  // Dual 4-stage shift register: rising clock (9, 1), active-high reset
  // (6, 14).  Clock edges detected on clk_sys; the reset clears the stage
  // outputs directly, as on the real part (see cd4013 above), ahead of the
  // propagation delay below.
  reg [3:0] a = 4'b0, b = 4'b0;
  reg ca_d = 1'b1, cb_d = 1'b1;
  always @(posedge clk_sys) begin
    ca_d <= p9;
    cb_d <= p1;
    if (p6)                  a <= 4'b0;
    else if (!ca_d && p9)    a <= {a[2:0], p7};
    if (p14)                 b <= 4'b0;
    else if (!cb_d && p1)    b <= {b[2:0], p15};
  end
  wire [3:0] ao = p6  ? 4'b0 : a;
  wire [3:0] bo = p14 ? 4'b0 : b;

  // A CD4015 at 5 V takes 250-400 ns from clock to output, and this board
  // depends on it.  D35's second half makes the horizontal display window
  // (O18_3 = NOR of its Q3 and Q4, among others), which opens and closes on
  // the same character-clock edges that start video fetches -- and which also
  // releases the preset of the CPU-arbitration flip-flop, D10, clocked by N_55
  // every 20 ticks.  Three things then depend on the delay:
  //   * closing: the 32nd character's fetch (its pixel strobe ~30 ticks after
  //     its slot edge) must finish first, or column 31 shows the idle bus --
  //     bright white garbage.  Needs the *rising* output delay >= ~40.
  //   * opening: the window must be open just *before* an N_55 edge, or the
  //     CPU's /MREQ can fall the same instant and the arbitration misses it;
  //     the CPU write then meets a video fetch (after the reset button, the
  //     memory test failed).  Needs the *falling* output delay <= 34.
  //   * opening, again: the video sequencer (D17) samples the window on F3_5M;
  //     at 53 it missed its edge and the fetches slid into the CPU's slots.
  // The window opens when the outputs fall and closes when one rises, and
  // real CMOS has different rise and fall delays (tPLH, tPHL), so each gets
  // its own: out = (copy delayed TPLH) AND (copy delayed TPHL), which rises
  // with the later and falls with the earlier.
  reg [7:0] dl [0:TPLH-1];
  integer k;
  always @(posedge clk_sys) begin
    dl[0] <= {ao, bo};
    for (k = 1; k < TPLH; k = k + 1) dl[k] <= dl[k-1];
  end
  wire [7:0] dout = dl[TPLH-1] & dl[TPHL-1];
  assign {p10, p3, p4, p5}    = dout[7:4];   // Q4 Q3 Q2 Q1
  assign {p2, p11, p12, p13}  = dout[3:0];
endmodule
