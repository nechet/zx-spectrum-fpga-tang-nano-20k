// Memory devices and the CPU as black boxes, so a synthesis run reports the
// board's *logic* on its own.  On an FPGA the memories become block RAM (or
// external PSRAM), not LUTs.
(* blackbox *) (* keep *)
module dram_x1 #(parameter ROWBITS = 8) (
    input p2, p3, p4, p5, p6, p7, p9, p10, p11, p12, p13, p15,
    output p14, input p8, p16);
endmodule

(* blackbox *) (* keep *)
module rom_27c128 #(parameter ROMFILE = "") (
    input p26, p23, p2, p21, p24, p25, p9, p10, p3, p4, p5, p6, p7, p8,
    input p20, p22, p1, p27,
    output p11, p12, p13, p15, p16, p17, p18, p19,
    input p14, p28);
endmodule

(* blackbox *) (* keep *)
module z80_chip (
    output p30, p31, p32, p33, p34, p35, p36, p37,
    output p38, p39, p40, p1, p2, p3, p4, p5,
    inout  p14, p15, p12, p8, p7, p9, p10, p13,
    input  p6, p16, p17, p24, p25, p26,
    output p18, p19, p20, p21, p22, p23, p27, p28,
    input  p11, p29);
endmodule
