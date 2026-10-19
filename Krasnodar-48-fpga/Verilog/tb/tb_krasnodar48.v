// -----------------------------------------------------------------------------
// Smoke test for the generated Krasnodar-48 netlist.
//
// Runs the board out of reset with a small ROM image and reports what the CPU
// fetches.  This checks that the netlist elaborates, that the ROM decode and
// the data bus work, and that the Z80 core runs -- it is not a functional model
// of the machine.
//
//   iverilog -g2005 -o sim tb/tb_krasnodar48.v krasnodar48.v lib/*.v \
//            third_party/tv80/*.v
//   ./sim +ROMFILE=tb/rom_test.hex
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_krasnodar48;

  reg clk14 = 1'b0;
  always #35.714 clk14 = ~clk14;        // 14 MHz

  reg res_n = 1'b0;
  wire [4:0] kd = 5'b11111;             // no key pressed
  wire vid_sync_n, vid_bright, vid_green, vid_blue, vid_red, tape_out, sound;
  wire [7:0] pa, pb;
  wire [7:0] pc;

  krasnodar48 dut (
      .clk14   (clk14),
      .KD1 (kd[0]), .KD2 (kd[1]), .KD3 (kd[2]), .KD4 (kd[3]), .KD5 (kd[4]),
      .tape_in (1'b0),
      .nmi_n   (1'b1),
      .jp_ru6  (1'b1),
      .wait_n  (1'b1),
      .busrq_n (1'b1),
      .res_n   (res_n),
      .vid_sync_n (vid_sync_n), .vid_bright (vid_bright),
      .vid_green  (vid_green),  .vid_blue   (vid_blue), .vid_red (vid_red),
      .tape_out (tape_out), .sound (sound),
      .PA0(pa[0]), .PA1(pa[1]), .PA2(pa[2]), .PA3(pa[3]),
      .PA4(pa[4]), .PA5(pa[5]), .PA6(pa[6]), .PA7(pa[7]),
      .PB0(pb[0]), .PB1(pb[1]), .PB2(pb[2]), .PB3(pb[3]),
      .PB4(pb[4]), .PB5(pb[5]), .PB6(pb[6]), .PB7(pb[7]),
      .PC0(pc[0]), .PC1(pc[1]), .PC2(pc[2]), .PC3(pc[3]),
      .PC4(pc[4]), .PC5(pc[5]), .PC6(pc[6]), .PC7(pc[7]));

  // The address and data buses are internal nets of the generated netlist.
  wire [15:0] a = {dut.A15, dut.A14, dut.A13, dut.A12, dut.A11, dut.A10,
                   dut.A9,  dut.A8,  dut.A7,  dut.A6,  dut.A5,  dut.A4,
                   dut.A3,  dut.A2,  dut.A1,  dut.A0};
  wire [7:0]  d = {dut.D7, dut.D6, dut.D5, dut.D4,
                   dut.D3, dut.D2, dut.D1, dut.D0};

  integer fetches = 0;
  reg [15:0] last = 16'hFFFF;
  reg seen_write = 1'b0, seen_read = 1'b0;

  // one line per opcode fetch (/M1, /MREQ and /RD all low), de-duplicated
  always @(posedge clk14)
    if (!dut.N_8 && !dut._MREQ && !dut._RD) begin
      if (a != last) begin
        if (fetches < 12)
          $display("  %7.2f us  M1 fetch  addr=%04h  data=%02h",
                   $realtime / 1000.0, a, d);
        fetches = fetches + 1;
        last = a;
      end
    end

  // the test program writes $AA to $4000 (video RAM) and reads it back
  always @(negedge dut._CAS5 or negedge dut._CAS6)
    if (!dut._WR5 || !dut._WR6) seen_write = 1'b1;
  always @(posedge clk14)
    if (!dut._MREQ && !dut._RD && dut.N_8 && a == 16'h4000) seen_read = 1'b1;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_krasnodar48.vcd");
      $dumpvars(0, tb_krasnodar48);
    end
    $display("Krasnodar-48 netlist smoke test");
    #2000 res_n = 1'b1;
    $display("  released /RESET at %0.2f us", $realtime / 1000.0);
    #200000;
    $display("");
    if (fetches == 0) begin
      $display("FAIL: the CPU never ran an opcode fetch");
      $finish(1);
    end
    $display("opcode fetches       : %0d", fetches);
    $display("DRAM write seen      : %s", seen_write ? "yes" : "no");
    $display("read back from $4000 : %s", seen_read ? "yes" : "no");
    $display("PASS");
    $finish;
  end
endmodule
