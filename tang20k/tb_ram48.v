// Integration test: the whole Krasnodar running testrom5, which checks the
// upper 32K of RAM and reports on the border (green pass, red fail).
//
// Built from ../core (see the run line in tb_ram48.sh).
`timescale 1ns / 1fs

module tb_ram48;
  reg clk = 1'b0, rst_i = 1'b0;
  wire [5:0] led;
  wire tmds_clk_p, tmds_clk_n; wire [2:0] tmds_d_p, tmds_d_n;
  always #18.518518 clk = ~clk;
  top #(.WITH_HDMI(0)) dut (.clk(clk), .rst_i(rst_i), .led(led),
           .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
           .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n));

  wire [3:0] bd = dut.kras.U_D61.q;        // {VBD1, tape, VBD2, VBD0}
  wire [2:0] grb = {bd[1], bd[3], bd[0]};  // green, red, blue

  // Reference memory: every CPU write to 8000-FFFF is recorded here; every
  // CPU read from there is checked against it, so a failure names the address.
  wire [15:0] ca = dut.kras.U_D1.a;
  wire [7:0]  cdo = dut.kras.U_D1.dout, cdi = dut.kras.U_D1.di;
  wire mreq_n = dut.kras.U_D1.mreq_n, rd_n = dut.kras.U_D1.rd_n, wr_n = dut.kras.U_D1.wr_n;
  reg [7:0] ref_mem [0:65535];
  reg [65535:0] known = 0;
  reg rd_d = 1'b1, wr_d = 1'b1, mreq_d = 1'b1;
  reg [15:0] a_d; reg [7:0] di_d;
  integer bad = 0, nrd = 0, nwr = 0;
  always @(posedge dut.clk_x5) begin
    rd_d <= rd_n; wr_d <= wr_n; mreq_d <= mreq_n; a_d <= ca; di_d <= cdi;
    if (!mreq_n && ca[15:14] != 2'b00 && !wr_n && wr_d) begin
      ref_mem[ca] <= cdo; known[ca] <= 1'b1; nwr = nwr + 1;
    end
    if (!mreq_d && a_d[15:14] != 2'b00 && rd_n && !rd_d && known[a_d]) begin
      nrd = nrd + 1;
      if (di_d !== ref_mem[a_d] && bad < 10) begin
        $display("  read %h = %h, wrote %h  (t=%0d us)", a_d, di_d, ref_mem[a_d], $time / 1000);
        bad = bad + 1;
      end
    end
  end

  initial begin
    #40_000_000 rst_i = 1'b1;              // release the CPU after the board reset
    wait (grb == 3'b100 || grb == 3'b010);
    if (grb == 3'b100) $display("PASS  upper 32K: border green at %0d ms", $time / 1_000_000);
    else               $display("FAIL  upper 32K: border red at %0d ms (%0d writes, %0d reads checked)", $time / 1_000_000, nwr, nrd);
    $finish;
  end
  initial begin
    #200_000_000 $display("FAIL  timeout, border GRB=%b", grb);
    $finish;
  end
endmodule
