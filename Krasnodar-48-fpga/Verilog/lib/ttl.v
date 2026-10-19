// -----------------------------------------------------------------------------
// 74LS / 74ALS parts used by Krasnodar-48, as behavioural models.
//
// Every port is named after its DIP pin (p1 … pN) so that the generated
// netlist can wire chips up mechanically, with no pin-name mapping to get
// wrong.  Supply pins are present but unused.
//
// See Tools/part-equivalents.md for the Soviet part each of these stands in
// for (К555ЛА3 = 74LS00, and so on).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// --- 74LS00  quad 2-input NAND ------------------------------------ К555ЛА3 --
module ttl_7400 (input p1, p2, p4, p5, p9, p10, p12, p13,
                 output p3, p6, p8, p11,
                 input p7, p14);
  assign p3  = ~(p1  & p2);
  assign p6  = ~(p4  & p5);
  assign p8  = ~(p9  & p10);
  assign p11 = ~(p12 & p13);
endmodule

// --- 74LS02  quad 2-input NOR ------------------------------------- К555ЛЕ1 --
module ttl_7402 (input p2, p3, p5, p6, p8, p9, p11, p12,
                 output p1, p4, p10, p13,
                 input p7, p14);
  assign p1  = ~(p2  | p3);
  assign p4  = ~(p5  | p6);
  assign p10 = ~(p8  | p9);
  assign p13 = ~(p11 | p12);
endmodule

// --- 74LS04  hex inverter ----------------------------------------- К555ЛН1 --
module ttl_7404 (input p1, p3, p5, p9, p11, p13,
                 output p2, p4, p6, p8, p10, p12,
                 input p7, p14);
  assign p2  = ~p1;
  assign p4  = ~p3;
  assign p6  = ~p5;
  assign p8  = ~p9;
  assign p10 = ~p11;
  assign p12 = ~p13;
endmodule

// --- 74LS08  quad 2-input AND ------------------------------------- К555ЛИ1 --
module ttl_7408 (input p1, p2, p4, p5, p9, p10, p12, p13,
                 output p3, p6, p8, p11,
                 input p7, p14);
  assign p3  = p1  & p2;
  assign p6  = p4  & p5;
  assign p8  = p9  & p10;
  assign p11 = p12 & p13;
endmodule

// --- 74LS10  triple 3-input NAND ---------------------------------- К555ЛА4 --
module ttl_7410 (input p1, p2, p13, p3, p4, p5, p9, p10, p11,
                 output p12, p6, p8,
                 input p7, p14);
  assign p12 = ~(p1 & p2  & p13);
  assign p6  = ~(p3 & p4  & p5);
  assign p8  = ~(p9 & p10 & p11);
endmodule

// --- 74LS32  quad 2-input OR -------------------------------------- К555ЛЛ1 --
module ttl_7432 (input p1, p2, p4, p5, p9, p10, p12, p13,
                 output p3, p6, p8, p11,
                 input p7, p14);
  assign p3  = p1  | p2;
  assign p6  = p4  | p5;
  assign p8  = p9  | p10;
  assign p11 = p12 | p13;
endmodule

// --- 74LS86  quad 2-input XOR ------------------------------------- К555ЛП5 --
module ttl_7486 (input p1, p2, p4, p5, p9, p10, p12, p13,
                 output p3, p6, p8, p11,
                 input p7, p14);
  assign p3  = p1  ^ p2;
  assign p6  = p4  ^ p5;
  assign p8  = p9  ^ p10;
  assign p11 = p12 ^ p13;
endmodule

// --- 74LS74  dual D flip-flop, async preset + clear ---------------- К555ТМ2 --
//   1=/CLR1 2=D1 3=CLK1 4=/PRE1 5=Q1 6=/Q1   13=/CLR2 12=D2 11=CLK2 10=/PRE2 9=Q2 8=/Q2
module ttl_7474 (input p1, p2, p3, p4, p10, p11, p12, p13,
                 output p5, p6, p8, p9,
                 input p7, p14);
  reg q1 = 1'b0, q2 = 1'b0;
  always @(posedge p3 or negedge p1 or negedge p4)
    if (!p1 && !p4) q1 <= 1'bx;      // both asserted: illegal
    else if (!p4)   q1 <= 1'b1;
    else if (!p1)   q1 <= 1'b0;
    else            q1 <= p2;
  always @(posedge p11 or negedge p13 or negedge p10)
    if (!p13 && !p10) q2 <= 1'bx;
    else if (!p10)    q2 <= 1'b1;
    else if (!p13)    q2 <= 1'b0;
    else              q2 <= p12;
  assign p5 = q1;
  assign p6 = ~q1;
  assign p9 = q2;
  assign p8 = ~q2;
endmodule

// --- 74LS175  quad D flip-flop, common clock + clear --------------- К555ТМ8 --
//   1=/CLR 9=CLK  D:4,5,12,13  Q:2,7,10,15  /Q:3,6,11,14
module ttl_74175 (input p1, p4, p5, p9, p12, p13,
                  output p2, p3, p6, p7, p10, p11, p14, p15,
                  input p8, p16);
  reg [3:0] q = 4'b0;
  always @(posedge p9 or negedge p1)
    if (!p1) q <= 4'b0;
    else     q <= {p13, p12, p5, p4};
  assign {p2, p3}   = { q[0], ~q[0]};
  assign {p7, p6}   = { q[1], ~q[1]};
  assign {p10, p11} = { q[2], ~q[2]};
  assign {p15, p14} = { q[3], ~q[3]};
endmodule

// --- 74ALS193  4-bit up/down binary counter ----------------------- К1533ИЕ7 --
//   15=A 1=B 10=C 9=D  11=/LOAD 14=CLR 5=UP 4=DOWN
//   3=QA 2=QB 6=QC 7=QD  12=/CARRY 13=/BORROW
module ttl_74193 (input p15, p1, p10, p9, p11, p14, p5, p4,
                  output p3, p2, p6, p7, p12, p13,
                  input p8, p16);
  reg [3:0] q = 4'b0;
  always @(posedge p14)     q <= 4'b0;                       // CLR is async
  always @(negedge p11) if (!p14) q <= {p9, p10, p1, p15};   // /LOAD is async
  always @(posedge p5)  if (!p14 && p11) q <= q + 4'd1;      // count up
  always @(posedge p4)  if (!p14 && p11) q <= q - 4'd1;      // count down
  assign {p7, p6, p2, p3} = q;
  assign p12 = ~(&q      & ~p5);      // carry  : ripples out on UP at 1111
  assign p13 = ~(~(|q)   & ~p4);      // borrow : ripples out on DOWN at 0000
endmodule

// --- 74ALS155  dual 2-to-4 decoder / demultiplexer ---------------- К1533ИД4 --
//   13=A 3=B  1=/1G 2=1C  15=/2G 14=/2C
//   The two halves are mirrored in the package: 1Y0..1Y3 run 7,6,5,4 while
//   2Y0..2Y3 run 9,10,11,12.  Confirmed by the memory map this produces on
//   D11 of this board -- ROM at 0000, video RAM at 4000.
module ttl_74155 (input p13, p3, p1, p2, p15, p14,
                  output p7, p6, p5, p4, p12, p11, p10, p9,
                  input p8, p16);
  wire [1:0] sel = {p3, p13};
  // Section 1: data input 1C (pin 1, the schematic's Ea) is active HIGH and
  // strobe /1G (pin 2, Sa) active LOW -- that asymmetry is what makes the
  // '155 a 1-of-8 demultiplexer.  This used to read ~p1 & p2, inverting both.
  // On this board pin 1 is /MREQ and pin 2 is A15, so the bug turned BLK0CPU
  // -- the contention look-ahead, "the CPU is about to touch 4000-7FFF before
  // /MREQ falls" -- into a decode of C000-FFFF with /MREQ active.  It never
  // fired for screen RAM, the CPU was never stalled, and its accesses walked
  // into video fetch cycles: writes landed in wrong cells and the ROM's memory
  // test failed.
  wire en1 =  p1 & ~p2;
  wire en2 = ~p15 & ~p14;
  assign p7  = ~(en1 & (sel == 2'd0));
  assign p6  = ~(en1 & (sel == 2'd1));
  assign p5  = ~(en1 & (sel == 2'd2));
  assign p4  = ~(en1 & (sel == 2'd3));
  assign p9  = ~(en2 & (sel == 2'd0));
  assign p10 = ~(en2 & (sel == 2'd1));
  assign p11 = ~(en2 & (sel == 2'd2));
  assign p12 = ~(en2 & (sel == 2'd3));
endmodule

// --- 74LS153  dual 4-to-1 multiplexer ------------------------------ К555КП2 --
//   14=A 2=B   1=/1G 6,5,4,3 = 1C0..1C3 -> 7=1Y
//              15=/2G 10,11,12,13 = 2C0..2C3 -> 9=2Y
module ttl_74153 (input p14, p2, p1, p6, p5, p4, p3, p15, p10, p11, p12, p13,
                  output p7, p9,
                  input p8, p16);
  wire [1:0] sel = {p2, p14};
  wire d1 = (sel == 2'd0) ? p6 : (sel == 2'd1) ? p5 : (sel == 2'd2) ? p4 : p3;
  wire d2 = (sel == 2'd0) ? p10 : (sel == 2'd1) ? p11 : (sel == 2'd2) ? p12 : p13;
  assign p7 = ~p1  & d1;
  assign p9 = ~p15 & d2;
endmodule

// --- 74LS253  dual 4-to-1 multiplexer, 3-state -------------------- К555КП12 --
//   same pinout as the '153; /G high releases the output instead of forcing 0
module ttl_74253 (input p14, p2, p1, p6, p5, p4, p3, p15, p10, p11, p12, p13,
                  output p7, p9,
                  input p8, p16);
  wire [1:0] sel = {p2, p14};
  wire d1 = (sel == 2'd0) ? p6 : (sel == 2'd1) ? p5 : (sel == 2'd2) ? p4 : p3;
  wire d2 = (sel == 2'd0) ? p10 : (sel == 2'd1) ? p11 : (sel == 2'd2) ? p12 : p13;
  assign p7 = p1  ? 1'bz : d1;
  assign p9 = p15 ? 1'bz : d2;
endmodule

// --- 74LS157  quad 2-to-1 multiplexer ---------------------------- КР555КП16 --
//   1=A/B select (0 -> A), 15=/G strobe (1 -> outputs low)
//   A:2,5,11,14   B:3,6,10,13   Y:4,7,9,12
module ttl_74157 (input p1, p15, p2, p3, p5, p6, p11, p10, p14, p13,
                  output p4, p7, p9, p12,
                  input p8, p16);
  wire e = ~p15;
  assign p4  = e & (p1 ? p3  : p2);
  assign p7  = e & (p1 ? p6  : p5);
  assign p9  = e & (p1 ? p10 : p11);
  assign p12 = e & (p1 ? p13 : p14);
endmodule

// --- 74LS257  quad 2-to-1 multiplexer, 3-state ------------------- К555КП11А --
//   same pinout as the '157; 15=/OE releases the outputs
module ttl_74257 (input p1, p15, p2, p3, p5, p6, p11, p10, p14, p13,
                  output p4, p7, p9, p12,
                  input p8, p16);
  assign p4  = p15 ? 1'bz : (p1 ? p3  : p2);
  assign p7  = p15 ? 1'bz : (p1 ? p6  : p5);
  assign p9  = p15 ? 1'bz : (p1 ? p10 : p11);
  assign p12 = p15 ? 1'bz : (p1 ? p13 : p14);
endmodule

// --- 74LS258  quad 2-to-1 multiplexer, inverting, 3-state --------- К555КП14 --
module ttl_74258 (input p1, p15, p2, p3, p5, p6, p11, p10, p14, p13,
                  output p4, p7, p9, p12,
                  input p8, p16);
  assign p4  = p15 ? 1'bz : ~(p1 ? p3  : p2);
  assign p7  = p15 ? 1'bz : ~(p1 ? p6  : p5);
  assign p9  = p15 ? 1'bz : ~(p1 ? p10 : p11);
  assign p12 = p15 ? 1'bz : ~(p1 ? p13 : p14);
endmodule

// --- 74LS295B  4-bit shift register, 3-state outputs -------------- К555ИР16 --
//   1=SER 2..5=A..D  6=MODE (1 = parallel load)  8=OE (1 = outputs driven)
//   9=CLK (falling edge)  13,12,11,10 = QA..QD
module ttl_74295 (input p1, p2, p3, p4, p5, p6, p8, p9,
                  output p13, p12, p11, p10,
                  input p7, p14);
  reg [3:0] q = 4'b0;
  always @(negedge p9)
    if (p6) q <= {p5, p4, p3, p2};        // parallel load  (QA..QD <= A..D)
    else    q <= {q[2:0], p1};            // shift right    (SER -> QA)
  assign p13 = p8 ? q[0] : 1'bz;   // QA
  assign p12 = p8 ? q[1] : 1'bz;   // QB
  assign p11 = p8 ? q[2] : 1'bz;   // QC
  assign p10 = p8 ? q[3] : 1'bz;   // QD
endmodule

// --- 74LS298  quad 2-input multiplexer with storage --------------- К555КП13 --
//   10=WS word select (0 -> "1" inputs)  11=CLK (falling edge)
//   pairs: QA(15)<-A1(3)/B1(4)  QB(14)<-A2(2)/B2(1)
//          QC(13)<-C1(9)/C2(5)  QD(12)<-D1(7)/D2(6)
// Quad 2-port register.  The four channels are A..D and the two ports 1 and 2:
//   A1=3  B1=4  C1=9  D1=7   -> port 1
//   A2=2  B2=1  C2=5  D2=6   -> port 2
//   Q1=15 Q2=14 Q3=13 Q4=12
// Pins 1..7 are not two tidy groups, so it is easy to pair them wrongly -- and
// the wrong pairing is nearly invisible.  On this board D61 is the port $FE
// latch, holding each output through port 1 and loading D0..D3 through port 2;
// swapping pins 2 and 4 makes the border bit recirculate a different bit
// instead of ever loading D0, so it never leaves its power-on value and the
// blue channel stays undefined.
module ttl_74298 (input p1, p2, p3, p4, p5, p6, p7, p9, p10, p11,
                  output p12, p13, p14, p15,
                  input p8, p16);
  reg [3:0] q = 4'b0;                       // {Q4, Q3, Q2, Q1}
  always @(negedge p11)
    q <= p10 ? {p6, p5, p1, p2}             // port 2: D2 C2 B2 A2
             : {p7, p9, p4, p3};            // port 1: D1 C1 B1 A1
  assign {p12, p13, p14, p15} = q;
endmodule
