// Integration test: the whole Krasnodar with the PS/2 keyboard, running
// testrom4 (border colour = keys A/S/D).  "Types" S over PS/2 and expects a red
// border; releases it and expects black; then A, blue.
//
// Built from ../core (see the run line in tb_kbd_sys.sh).
`timescale 1ns / 1fs

module tb_kbd_sys;
  reg clk = 1'b0, rst_i = 1'b0;
  wire [5:0] led;
  wire tmds_clk_p, tmds_clk_n; wire [2:0] tmds_d_p, tmds_d_n;
  reg ps2_clk = 1'b1, ps2_data = 1'b1;
  always #18.518518 clk = ~clk;
  top #(.WITH_HDMI(0)) dut (.clk(clk), .rst_i(rst_i), .led(led),
           .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
           .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
           .ps2_clk(ps2_clk), .ps2_data(ps2_data));

  wire [3:0] bd = dut.kras.U_D61.q;        // {VBD1, tape, VBD2, VBD0}
  wire [2:0] grb = {bd[1], bd[3], bd[0]};  // green, red, blue
  integer fails = 0;

  task send_byte(input [7:0] b);
    integer i; reg [10:0] f;
    begin
      f = {1'b1, ~^b, b, 1'b0};
      for (i = 0; i < 11; i = i + 1) begin
        ps2_data = f[i];
        #20_000 ps2_clk = 1'b0;
        #40_000 ps2_clk = 1'b1;
        #20_000;
      end
      #200_000;
    end
  endtask

  task expect_border(input [2:0] want, input [8*24-1:0] what);
    begin
      #200_000;                           // a few hundred loop passes
      if (grb === want) $display("PASS  %0s: border GRB=%b", what, grb);
      else begin $display("FAIL  %0s: border GRB=%b, want %b", what, grb, want); fails = fails + 1; end
    end
  endtask

  initial begin
    #40_000_000 rst_i = 1'b1;             // release the CPU after the board reset
    #1_000_000;
    expect_border(3'b000, "nothing pressed");
    send_byte(8'h1B);                     // S down
    expect_border(3'b010, "S held -> red");
    send_byte(8'hF0); send_byte(8'h1B);   // S up
    expect_border(3'b000, "S released -> black");
    send_byte(8'h1C);                     // A down
    expect_border(3'b001, "A held -> blue");
    send_byte(8'h23);                     // D down too
    expect_border(3'b101, "A+D held -> cyan");
    $display("");
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
  end
endmodule
