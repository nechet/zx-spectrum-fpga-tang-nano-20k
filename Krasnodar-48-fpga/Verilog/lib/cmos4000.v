// -----------------------------------------------------------------------------
// CD4000B-series parts used by Krasnodar-48 (К561 originals).
// Ports are named after the DIP pin; supply pins are present but unused.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// --- CD4001B  quad 2-input NOR ------------------------------------ К561ЛЕ5 --
//   (1,2)->3   (5,6)->4   (8,9)->10   (12,13)->11
module cd4001 (input p1, p2, p5, p6, p8, p9, p12, p13,
               output p3, p4, p10, p11,
               input p7, p14);
  assign p3  = ~(p1  | p2);
  assign p4  = ~(p5  | p6);
  assign p10 = ~(p8  | p9);
  assign p11 = ~(p12 | p13);
endmodule

// --- CD4011B  quad 2-input NAND ----------------------------------- К561ЛА7 --
module cd4011 (input p1, p2, p5, p6, p8, p9, p12, p13,
               output p3, p4, p10, p11,
               input p7, p14);
  assign p3  = ~(p1  & p2);
  assign p4  = ~(p5  & p6);
  assign p10 = ~(p8  & p9);
  assign p11 = ~(p12 & p13);
endmodule

// --- CD4069UB  hex inverter --------------------------------------- К561ЛН2 --
module cd4069 (input p1, p3, p5, p9, p11, p13,
               output p2, p4, p6, p8, p10, p12,
               input p7, p14);
  assign p2  = ~p1;
  assign p4  = ~p3;
  assign p6  = ~p5;
  assign p8  = ~p9;
  assign p10 = ~p11;
  assign p12 = ~p13;
endmodule

// --- CD4013B  dual D flip-flop ------------------------------------ К561ТМ2 --
//   1=Q1 2=/Q1 3=CLK1 4=RST1 5=D1 6=SET1
//   13=Q2 12=/Q2 11=CLK2 10=RST2 9=D2 8=SET2      (RST/SET are active high)
// Pinout.  The first half follows the CD4013, the second half does NOT:
//   FF1  1=Q1  2=/Q1  3=CLK1  4=RESET1  5=D1  6=SET1
//   FF2 13=Q2 12=/Q2 11=CLK2 10=RESET2  9=D2  8=SET2
// A CD4013 has 12=Q2, 11=/Q2, 10=CLK2, 13=RESET2.  The К561ТМ2 symbol in the
// board's own library is pinned as above, and the circuit only makes sense
// that way: D34's pin 13 drives N$125, which pin 5 then reads back, and pin 11
// takes V3 through R22.  Read as a CD4013 instead, N$125 has no driver at all
// and the vertical timing chain stops -- which is exactly what happened when
// this was "corrected" to the datasheet.
module cd4013 (input p3, p4, p5, p6, p8, p9, p10, p11,
               output p1, p2, p12, p13,
               input p7, p14);
  reg q1 = 1'b0, q2 = 1'b0;
  always @(posedge p3 or posedge p4 or posedge p6)
    if (p4)      q1 <= 1'b0;
    else if (p6) q1 <= 1'b1;
    else         q1 <= p5;
  always @(posedge p11 or posedge p10 or posedge p8)
    if (p10)     q2 <= 1'b0;
    else if (p8) q2 <= 1'b1;
    else         q2 <= p9;
  assign p1  =  q1;
  assign p2  = ~q1;
  assign p13 =  q2;
  assign p12 = ~q2;
endmodule

// --- CD4015B  dual 4-stage static shift register ------------------ К561ИР2 --
//   A: 1=CLK 7=DATA 6=RST  outputs 5,4,3,2 = Q1..Q4
//   B: 9=CLK 15=DATA 14=RST outputs 13,12,11,10 = Q1..Q4
// The two halves are interleaved in the package, which is easy to get wrong:
//   A:  CLOCK 9   RESET 6   DATA 7    Q1..Q4 = 5, 4, 3, 10
//   B:  CLOCK 1   RESET 14  DATA 15   Q1..Q4 = 13, 12, 11, 2
// Only Q4 crosses over -- A's is 10, next to B's outputs, and B's is 2, next
// to A's.  Pairing 1 with 6/7 and 9 with 14/15 instead leaves D35 shifting on
// the wrong edge and the line counter never reaches the sync comparator.
module cd4015 (input p1, p7, p6, p9, p15, p14,
               output p5, p4, p3, p2, p13, p12, p11, p10,
               input p8, p16);
  reg [3:0] a = 4'b0, b = 4'b0;
  always @(posedge p9 or posedge p6)
    if (p6) a <= 4'b0; else a <= {a[2:0], p7};
  always @(posedge p1 or posedge p14)
    if (p14) b <= 4'b0; else b <= {b[2:0], p15};
  assign {p10, p3, p4, p5}    = a;      // Q4 Q3 Q2 Q1
  assign {p2, p11, p12, p13}  = b;
endmodule

// --- CD4520B  dual 4-bit binary up counter ------------------------ К561ИЕ10 --
//   A: 1=CLK 2=EN 7=RST  outputs 3,4,5,6 = Q0..Q3
//   B: 9=CLK 10=EN 15=RST outputs 11,12,13,14 = Q0..Q3
//   Counts on a rising CLK while EN is high, or on a falling EN while CLK is low.
module cd4520 (input p1, p2, p7, p9, p10, p15,
               output p3, p4, p5, p6, p11, p12, p13, p14,
               input p8, p16);
  reg [3:0] a = 4'b0, b = 4'b0;
  always @(posedge p1 or posedge p7)
    if (p7) a <= 4'b0; else if (p2) a <= a + 4'd1;
  always @(negedge p2) if (!p7 && !p1) a <= a + 4'd1;
  always @(posedge p9 or posedge p15)
    if (p15) b <= 4'b0; else if (p10) b <= b + 4'd1;
  always @(negedge p10) if (!p15 && !p9) b <= b + 4'd1;
  assign {p6, p5, p4, p3}     = a;
  assign {p14, p13, p12, p11} = b;
endmodule
