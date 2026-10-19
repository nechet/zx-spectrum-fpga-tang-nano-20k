// -----------------------------------------------------------------------------
// External memory devices: the DRAMs and the EPROM are separate chips on this
// board, so they are separate modules here too.
// Ports are named after the DIP pin.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

// --- 1-bit-wide DRAM on the 4164 pinout --------------- КР565РУ5Д / КР565РУ6Г --
//   2=DIN 3=/WE 4=/RAS 5=A0 6=A2 7=A1 9=A7 10=A5 11=A4 12=A3 13=A6 14=DOUT 15=/CAS
//   ROWBITS 8 -> 64K x 1 (4164, КР565РУ5).  ROWBITS 7 -> 16K x 1 (КР565РУ6);
//   there A7 (pin 9) is unused, which is why the board ties it low so that a
//   64K part can be fitted instead.
module dram_x1 #(parameter ROWBITS = 8) (
    input  p2, p3, p4, p5, p6, p7, p9, p10, p11, p12, p13, p15,
    output p14,
    input  p8, p16);

  localparam AW = 2 * ROWBITS;
  wire [7:0] addr = {p9, p13, p10, p11, p12, p6, p7, p5};   // A7..A0
  wire [ROWBITS-1:0] a = addr[ROWBITS-1:0];

  reg mem [0:(1 << AW) - 1];
  reg [ROWBITS-1:0] row = {ROWBITS{1'b0}};
  reg dout = 1'b1;
  reg driving = 1'b0;
  integer i;

  initial for (i = 0; i < (1 << AW); i = i + 1) mem[i] = 1'b0;

  always @(negedge p4) row <= a;                            // /RAS latches the row

  always @(negedge p15) begin                               // /CAS latches the column
    if (!p4) begin
      if (!p3) begin                                        // write
        mem[{row, a}] <= p2;
        driving <= 1'b0;                                    // early write: output stays Z
      end else begin                                        // read
        dout <= mem[{row, a}];
        driving <= 1'b1;
      end
    end
  end

  always @(posedge p15) driving <= 1'b0;                    // output released with /CAS

  assign p14 = driving ? dout : 1'bz;
endmodule

// --- 27C128  16K x 8 EPROM ------------------------------------------ D15 -----
//   1=Vpp 2=A12 3=A7 4=A6 5=A5 6=A4 7=A3 8=A2 9=A1 10=A0
//   11..13,15..19 = D0..D7   20=/CE  21=A10  22=/OE  23=A11  24=A9  25=A8
//   26=A13  27=/PGM
//   Load an image with +ROMFILE=<file> (Intel-hex-free plain hex, one byte per
//   line) or by overriding the ROMFILE parameter.
module rom_27c128 #(parameter ROMFILE = "") (
    input  p26, p23, p2, p21, p24, p25, p9, p10, p3, p4, p5, p6, p7, p8,
    input  p20, p22, p1, p27,
    output p11, p12, p13, p15, p16, p17, p18, p19,
    input  p14, p28);

  wire [13:0] a = {p26, p2, p23, p21, p24, p25, p3, p4, p5, p6, p7, p8, p9, p10};
  reg [7:0] mem [0:16383];
  reg [7:0] d;
  integer i;
  reg [1023:0] file;

  initial begin
    for (i = 0; i < 16384; i = i + 1) mem[i] = 8'hFF;
    if (ROMFILE != "") $readmemh(ROMFILE, mem);
    else if ($value$plusargs("ROMFILE=%s", file)) $readmemh(file, mem);
  end

  always @(*) d = mem[a];

  wire oe = ~p20 & ~p22;
  assign {p19, p18, p17, p16, p15, p13, p12, p11} = oe ? d : 8'bz;
endmodule
