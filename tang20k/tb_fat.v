// Unit test of fat32.v (on sd_spi.v and the card model) with the image from
// mk_fat_image.py: mount, list the games, read each one whole and compare its
// size and checksum.  Expected values: tb_fat_expect.vh.
`timescale 1ns / 1ps
module tb_fat;
  reg clk = 1'b0;
  always #3.7037 clk = ~clk;

  wire sck, cs_n, mosi, miso;
  reg  start = 1'b0;
  wire sd_rd, sd_ready, sd_err, sd_dvalid, sdhc; wire [31:0] sd_lba; wire [7:0] sd_dout; wire [3:0] sd_ec;
  sd_spi #(.CLK_HZ(135_000_000), .SLOW_HZ(4_000_000), .FAST_HALF(1)) sd (
      .clk(clk), .start(start), .sd_sck(sck), .sd_cs_n(cs_n), .sd_mosi(mosi), .sd_miso(miso),
      .rd(sd_rd), .lba(sd_lba), .dout(sd_dout), .dout_valid(sd_dvalid), .ready(sd_ready),
      .err(sd_err), .err_code(sd_ec), .sdhc(sdhc));
  sd_card_model #(.IMAGE("tb_fat_image.hex"), .SECTORS(512)) card (.sck(sck), .cs_n(cs_n), .mosi(mosi), .miso(miso));

  reg mount = 0, first = 0, next = 0, open = 0, take = 0;
  reg [31:0] open_clus = 0, open_size = 0;
  wire busy, mounted, err, ent_valid, dir_end, dvalid, eof; wire [3:0] ec;
  wire [87:0] ent_name; wire [31:0] ent_size, ent_clus; wire [7:0] dout;
  fat32 fs (.clk(clk), .mount(mount), .first(first), .next(next), .open(open),
      .open_clus(open_clus), .open_size(open_size), .busy(busy), .mounted(mounted),
      .err(err), .err_code(ec), .ent_valid(ent_valid), .dir_end(dir_end),
      .ent_name(ent_name), .ent_size(ent_size), .ent_clus(ent_clus),
      .dout(dout), .dvalid(dvalid), .eof(eof), .take(take),
      .sd_rd(sd_rd), .sd_lba(sd_lba), .sd_dout(sd_dout), .sd_dvalid(sd_dvalid),
      .sd_ready(sd_ready), .sd_err(sd_err));

  `include "tb_fat_expect.vh"

  // the reader: take every byte offered, checksum it
  reg [31:0] c = 0, n = 0;
  always @(posedge clk) begin
    take <= dvalid && !take;
    if (take) begin c <= c * 31 + dout; n <= n + 1; end
  end

  // (a task with an inout argument would only copy the value back at its end)
`define PULSE(s) begin @(posedge clk) s <= 1; @(posedge clk) s <= 0; @(posedge clk); end

  integer i, fails = 0;
  initial begin
    `PULSE(start)
    wait (sd_ready || sd_err);
    `PULSE(mount)
    wait (!busy);
    if (!mounted) begin $display("FAIL  mount: err %h", ec); $finish; end
    $display("PASS  mounted: FAT at %0d, data at %0d, root cluster %0d, %0d sectors/cluster",
             fs.fat_lba, fs.data_lba, fs.root, 1 << fs.spc_log2);
    `PULSE(first)
    for (i = 0; i <= NEXP; i = i + 1) begin
      wait (!busy);
      if (i == NEXP) begin
        if (dir_end && !ent_valid) $display("PASS  end of folder after %0d games", NEXP);
        else begin $display("FAIL  expected end of folder, got \"%s\"", ent_name); fails = fails + 1; end
      end else if (!ent_valid) begin
        $display("FAIL  game %0d missing (dir_end=%0d err=%0d)", i, dir_end, err); fails = fails + 1; i = NEXP;
      end else begin
        if (ent_name !== exp_name[i] || ent_clus !== exp_clus[i] || ent_size !== exp_size[i]) begin
          $display("FAIL  entry %0d: \"%s\" clus %0d size %0d", i, ent_name, ent_clus, ent_size); fails = fails + 1;
        end
        // read it, then continue the listing (the buffer is shared: tests re-loading)
        open_clus = ent_clus; open_size = ent_size; c = 0; n = 0;
        `PULSE(open)
        wait (eof || err);
        @(posedge clk); @(posedge clk);
        if (err || n !== exp_size[i] || c !== exp_chk[i]) begin
          $display("FAIL  read \"%s\": %0d bytes, chk %h (want %0d, %h), err %h", ent_name, n, c, exp_size[i], exp_chk[i], ec);
          fails = fails + 1;
        end else
          $display("PASS  \"%s\" cluster %0d: %0d bytes, checksum %h", ent_name, ent_clus, n, c);
        `PULSE(next)
      end
    end
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
  end
  initial begin #200_000_000 $display("FAIL  timeout (state %0d)", fs.st); $finish; end
endmodule
