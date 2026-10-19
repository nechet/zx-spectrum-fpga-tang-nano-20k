// sd_list.v against the card model with the mk_fat_image.py image: print what
// the board would send.
`timescale 1ns / 1ps
module tb_sd_list;
  wire sck, cs_n, mosi, miso, tx; wire [5:0] led;
  sd_list dut (.clk(1'b0), .rst_i(1'b0), .led(led), .sd_clk(sck), .sd_cmd(mosi),
               .sd_dat3(cs_n), .sd_dat0(miso), .uart_tx(tx));
  sd_card_model #(.IMAGE("tb_fat_image.hex"), .SECTORS(512)) card (.sck(sck), .cs_n(cs_n), .mosi(mosi), .miso(miso));
  localparam real BIT = 1e9 / 115200;
  integer i; reg [7:0] c;
  initial forever begin
    @(negedge tx); #(BIT * 1.5);
    for (i = 0; i < 8; i = i + 1) begin c[i] = tx; #(BIT); end
    if (c != 8'h0D) $write("%c", c);
    if (dut.q == 4'd11 && c == 8'h0A) $finish;
  end
  initial begin #900_000_000 $display("TIMEOUT q=%0d", dut.q); $finish; end
endmodule
