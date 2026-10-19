// -----------------------------------------------------------------------------
// Z80 CPU in a 40-pin DIP wrapper (D1 on this board).
//
// The core is TV80 by Guy Hutchison -- a Verilog port of Daniel Wallner's T80 --
// vendored under third_party/tv80/ (MIT licence).  TV80 presents separate `di`
// and `dout` buses; this wrapper adds the bidirectional data bus and maps
// everything onto real Z80 pin numbers:
//
//   A0..A15 = 30,31,32,33,34,35,36,37,38,39,40,1,2,3,4,5
//   D0..D7  = 14,15,12,8,7,9,10,13
//   6=CLK 16=/INT 17=/NMI 18=/HALT 19=/MREQ 20=/IORQ 21=/RD 22=/WR
//   23=/BUSAK 24=/WAIT 25=/BUSRQ 26=/RESET 27=/M1 28=/RFSH
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module z80_chip (
    output p30, p31, p32, p33, p34, p35, p36, p37,     // A0..A7
    output p38, p39, p40, p1, p2, p3, p4, p5,          // A8..A15
    inout  p14, p15, p12, p8, p7, p9, p10, p13,        // D0..D7
    input  p6,                                          // CLK
    input  p16, p17, p24, p25, p26,                     // /INT /NMI /WAIT /BUSRQ /RESET
    output p18, p19, p20, p21, p22, p23, p27, p28,      // /HALT /MREQ /IORQ /RD /WR /BUSAK /M1 /RFSH
    input  p11, p29);

  wire [15:0] a;
  wire [7:0]  dout;
  wire [7:0]  di = {p13, p10, p9, p7, p8, p12, p15, p14};
  wire mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, halt_n, busak_n;

  // T2Write(0): /WR asserted from the falling clock edge in T2 to the one in
  // T3, which is the real Z80's write strobe.  T2Write(1) asserts it from the
  // falling edge in T1 -- half a clock before tv80 loads dout at the end of T1
  // -- so the start of every write strobe carried the previous byte.  This
  // board's DRAM does late writes, committing at the first instant /RAS, /CAS
  // and /WE are all low, which landed in that half clock: the test ROM's
  // LD (HL),38h stored 02 (the last byte read), and every screen write was
  // wrong on hardware and in simulation alike.
  tv80n #(.Mode(0), .T2Write(0), .IOWait(1)) core (
      .reset_n (p26),
      .clk     (p6),
      .wait_n  (p24),
      .int_n   (p16),
      .nmi_n   (p17),
      .busrq_n (p25),
      .di      (di),
      .m1_n    (m1_n),
      .mreq_n  (mreq_n),
      .iorq_n  (iorq_n),
      .rd_n    (rd_n),
      .wr_n    (wr_n),
      .rfsh_n  (rfsh_n),
      .halt_n  (halt_n),
      .busak_n (busak_n),
      .A       (a),
      .dout    (dout));

  assign {p37, p36, p35, p34, p33, p32, p31, p30} = a[7:0];    // A7..A0
  assign {p5, p4, p3, p2, p1, p40, p39, p38}      = a[15:8];   // A15..A8

  // The CPU only drives the data bus while it is writing; the rest of the time
  // it is released so the ROM, RAM, PPI and multiplexers can drive it.
  //
  // /BUSAK is active low and idles HIGH, like the /MREQ and /RD gating just
  // below.  Writing ~busak_n here made the term permanently zero, so the CPU
  // never drove the bus at all: every write went out as FF -- the value of an
  // idle wired-AND bus -- while addresses, /WR and timing all looked perfect.
  // The machine got as far as initialising its system variables and then
  // filled them, the stack and the screen with FF.
  wire drive = ~wr_n & busak_n;
  assign {p13, p10, p9, p7, p8, p12, p15, p14} = drive ? dout : 8'bz;

  assign p18 = halt_n;
  assign p19 = busak_n ? mreq_n : 1'bz;
  assign p20 = busak_n ? iorq_n : 1'bz;
  assign p21 = busak_n ? rd_n   : 1'bz;
  assign p22 = busak_n ? wr_n   : 1'bz;
  assign p23 = busak_n;
  assign p27 = m1_n;
  assign p28 = rfsh_n;
endmodule
