// Unit test of sd_spi.v against sd_card_model.v: initialise, read sectors 0
// and 5, compare every byte with the model's image.
`timescale 1ns / 1ps
module tb_sd;
  reg clk = 1'b0;
  always #3.7037 clk = ~clk;                   // 135 MHz

  wire sck, cs_n, mosi, miso;
  reg  start = 1'b0, rd = 1'b0;
  reg  [31:0] lba = 32'd0;
  wire [7:0] dout; wire dout_valid, ready, err, sdhc; wire [3:0] err_code;

  // SLOW_HZ raised to keep the simulation short; same logic, faster wake-up
  sd_spi #(.CLK_HZ(135_000_000), .SLOW_HZ(4_000_000), .FAST_HALF(4)) dut (
      .clk(clk), .start(start), .sd_sck(sck), .sd_cs_n(cs_n), .sd_mosi(mosi),
      .sd_miso(miso), .rd(rd), .lba(lba), .dout(dout), .dout_valid(dout_valid),
      .ready(ready), .err(err), .err_code(err_code), .sdhc(sdhc));
  sd_card_model #(.SDHC(`SDHC)) card (.sck(sck), .cs_n(cs_n), .mosi(mosi), .miso(miso));

  integer nb, bad, fails = 0;
  always @(posedge clk) if (dout_valid) begin
    if (dout !== card.image[lba * 512 + nb] && bad < 5) begin
      $display("  sector %0d byte %0d: got %h want %h", lba, nb, dout, card.image[lba * 512 + nb]);
      bad = bad + 1;
    end
    nb = nb + 1;
  end

  task read_sector(input [31:0] s);
    begin
      nb = 0; bad = 0;
      @(posedge clk) begin lba <= s; rd <= 1'b1; end
      @(posedge clk) rd <= 1'b0;
      @(posedge clk);
      wait (ready || err);
      if (err) begin $display("FAIL  read %0d: err %h", s, err_code); fails = fails + 1; end
      else if (nb != 512 || bad) begin $display("FAIL  read %0d: %0d bytes, %0d wrong", s, nb, bad); fails = fails + 1; end
      else $display("PASS  sector %0d: 512 bytes match", s);
    end
  endtask

  initial begin
    #100 @(posedge clk) start <= 1'b1;
    @(posedge clk) start <= 1'b0;
    wait (ready || err);
    if (err) begin $display("FAIL  init: err %h", err_code); $finish; end
    $display("PASS  init at %0d us: sdhc=%0d, %0d commands", $time / 1000, sdhc, card.ncmds);
    read_sector(0);
    read_sector(5);
    if (fails == 0) $display("ALL PASSED"); else $display("FAILED");
    $finish;
  end
  initial begin #20_000_000 $display("FAIL  timeout"); $finish; end
endmodule
