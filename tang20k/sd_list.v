// -----------------------------------------------------------------------------
// FAT32 test top (gowin_sdtest, step 2): mount the card, list the games in the
// root folder, read each one whole, and print on /dev/ttyUSB1 (115200 8N1):
//
//   CHUCKIE Z80 size 0000C01E clus 00000003 chk 1A2B3C4D
//   ...
//   7 files
//
// chk = (chk * 31 + byte) over the whole file, as mk_fat_image.py and the PC
// side compute it, so a line that matches proves name, size, cluster chain and
// every byte.  Button S1 runs it again.  LEDs: 0 mounted, 1 error, 5 heartbeat.
//
// All of it runs on the board's 27 MHz clock, not the 135 MHz PLL output:
// the card needs nothing faster, and the FAT32 state machine's 32-bit
// arithmetic missed 135 MHz timing (Fmax 85-112 MHz) while having five times
// the margin at 27.
// -----------------------------------------------------------------------------
`default_nettype none

module sd_list (
    input  wire       clk,          // 27 MHz
    input  wire       rst_i,        // button S1, active high
    output wire [5:0] led,
    output wire       sd_clk, sd_cmd, sd_dat3,
    input  wire       sd_dat0,
    output wire       uart_tx
);
  wire clk27;
`ifdef SIM
  reg sclk = 1'b0; always #18.5185 sclk = ~sclk;
  assign clk27 = sclk;
`else
  assign clk27 = clk;
`endif
  wire lock = 1'b1;

  reg [2:0]  btn = 3'b000;
  reg [19:0] boot = `ifdef SIM 20'hFFF00 `else 20'd0 `endif;   // ~39 ms
  reg        start = 1'b0;
  always @(posedge clk27) begin
    btn <= {btn[1:0], rst_i};
    start <= 1'b0;
    if (lock && !(&boot)) begin boot <= boot + 20'd1; if (boot == 20'hFFFFE) start <= 1'b1; end
    if (btn[2:1] == 2'b01) start <= 1'b1;
  end

  // --- card and filesystem ------------------------------------------------------
  wire sd_rd, sd_ready, sd_err, sd_dvalid, sdhc; wire [31:0] sd_lba; wire [7:0] sd_dout; wire [3:0] sd_ec;
  sd_spi #(.CLK_HZ(27_000_000), .FAST_HALF(1)) sd (
      .clk(clk27), .start(start), .sd_sck(sd_clk), .sd_cs_n(sd_dat3), .sd_mosi(sd_cmd),
      .sd_miso(sd_dat0), .rd(sd_rd), .lba(sd_lba), .dout(sd_dout), .dout_valid(sd_dvalid),
      .ready(sd_ready), .err(sd_err), .err_code(sd_ec), .sdhc(sdhc));

  reg mount = 1'b0, first = 1'b0, next = 1'b0, open = 1'b0, take = 1'b0;
  wire busy, mounted, fs_err, ent_valid, dir_end, dvalid, eof; wire [3:0] fs_ec;
  wire [87:0] ent_name; wire [31:0] ent_size, ent_clus; wire [7:0] dout;
  fat32 fs (.clk(clk27), .mount(mount), .first(first), .next(next), .open(open),
      .open_clus(ent_clus), .open_size(ent_size), .busy(busy), .mounted(mounted),
      .err(fs_err), .err_code(fs_ec), .ent_valid(ent_valid), .dir_end(dir_end),
      .ent_name(ent_name), .ent_size(ent_size), .ent_clus(ent_clus),
      .dout(dout), .dvalid(dvalid), .eof(eof), .take(take),
      .sd_rd(sd_rd), .sd_lba(sd_lba), .sd_dout(sd_dout), .sd_dvalid(sd_dvalid),
      .sd_ready(sd_ready), .sd_err(sd_err));

  // --- serial out ----------------------------------------------------------------
  reg  [7:0] ch = 8'h00;
  reg        send = 1'b0;
  wire       tx_idle;
  uart_tx #(.CLK_HZ(27_000_000)) tx (.clk(clk27), .data(ch), .send(send), .idle(tx_idle), .tx(uart_tx));
  function [7:0] hexc(input [3:0] n); hexc = (n < 4'd10) ? 8'h30 + n : 8'h37 + n; endfunction

  // One line, built as up to 64 characters and then sent.
  reg [7:0] line [0:63];
  reg [6:0] llen = 7'd0, lpos = 7'd0;
  reg [31:0] chk = 32'd0;
  reg [7:0]  nfiles = 8'd0;
  integer i;

  localparam [3:0] Q_IDLE = 4'd0, Q_INIT = 4'd1, Q_MNT = 4'd2, Q_FIRST = 4'd3, Q_ENT = 4'd4,
                   Q_READ = 4'd5, Q_LINE = 4'd6, Q_SEND = 4'd7, Q_NEXT = 4'd8, Q_ERR = 4'd9,
                   Q_TOTAL = 4'd10, Q_STOP = 4'd11;
  reg [3:0] q = Q_IDLE, q_after = Q_IDLE;

  always @(posedge clk27) begin
    mount <= 1'b0; first <= 1'b0; next <= 1'b0; open <= 1'b0; send <= 1'b0;
    take <= dvalid && !take && q == Q_READ;
    if (take) chk <= chk * 32'd31 + {24'd0, dout};

    if (start) q <= Q_INIT;
    else case (q)
      Q_IDLE, Q_STOP: ;
      Q_INIT:  if (sd_err) q <= Q_ERR;
               else if (sd_ready) begin mount <= 1'b1; q <= Q_MNT; end
      Q_MNT:   if (!busy && !mount) begin
                 if (!mounted) q <= Q_ERR;
                 else begin first <= 1'b1; nfiles <= 8'd0; q <= Q_ENT; end
               end
      Q_ENT:   if (!busy && !first && !next) begin
                 if (ent_valid) begin chk <= 32'd0; open <= 1'b1; q <= Q_READ; end
                 else if (dir_end) q <= Q_TOTAL;
                 else q <= Q_ERR;
               end
      Q_READ:  if (fs_err) q <= Q_ERR;
               else if (eof && !open && !take) begin
                 // "NAME    EXT size XXXXXXXX clus XXXXXXXX chk XXXXXXXX\r\n"
                 for (i = 0; i < 8; i = i + 1) line[i] <= ent_name[87 - 8*i -: 8];
                 line[8] <= " ";
                 for (i = 0; i < 3; i = i + 1) line[9 + i] <= ent_name[23 - 8*i -: 8];
                 line[12] <= " "; line[13] <= "s"; line[14] <= "i"; line[15] <= "z"; line[16] <= "e"; line[17] <= " ";
                 for (i = 0; i < 8; i = i + 1) line[18 + i] <= hexc(ent_size[31 - 4*i -: 4]);
                 line[26] <= " "; line[27] <= "c"; line[28] <= "l"; line[29] <= "u"; line[30] <= "s"; line[31] <= " ";
                 for (i = 0; i < 8; i = i + 1) line[32 + i] <= hexc(ent_clus[31 - 4*i -: 4]);
                 line[40] <= " "; line[41] <= "c"; line[42] <= "h"; line[43] <= "k"; line[44] <= " ";
                 for (i = 0; i < 8; i = i + 1) line[45 + i] <= hexc(chk[31 - 4*i -: 4]);
                 line[53] <= 8'h0D; line[54] <= 8'h0A;
                 llen <= 7'd55; lpos <= 7'd0; q_after <= Q_NEXT; q <= Q_SEND;
                 nfiles <= nfiles + 8'd1;
               end
      Q_SEND:  if (tx_idle && !send) begin
                 if (lpos == llen) q <= q_after;
                 else begin ch <= line[lpos]; send <= 1'b1; lpos <= lpos + 7'd1; end
               end
      Q_NEXT:  begin next <= 1'b1; q <= Q_ENT; end
      Q_TOTAL: begin
                 line[0] <= hexc(nfiles[7:4]); line[1] <= hexc(nfiles[3:0]);
                 line[2] <= " "; line[3] <= "f"; line[4] <= "i"; line[5] <= "l"; line[6] <= "e"; line[7] <= "s";
                 line[8] <= 8'h0D; line[9] <= 8'h0A;
                 llen <= 7'd10; lpos <= 7'd0; q_after <= Q_STOP; q <= Q_SEND;
               end
      Q_ERR:   begin                                  // "ERROR sd X fs X\r\n"
                 line[0] <= "E"; line[1] <= "R"; line[2] <= "R"; line[3] <= " ";
                 line[4] <= "s"; line[5] <= "d"; line[6] <= " "; line[7] <= hexc(sd_ec);
                 line[8] <= " "; line[9] <= "f"; line[10] <= "s"; line[11] <= " "; line[12] <= hexc(fs_ec);
                 line[13] <= 8'h0D; line[14] <= 8'h0A;
                 llen <= 7'd15; lpos <= 7'd0; q_after <= Q_STOP; q <= Q_SEND;
               end
      default: q <= Q_IDLE;
    endcase
  end

  reg [24:0] beat = 25'd0;
  always @(posedge clk27) beat <= beat + 25'd1;
  assign led = ~{beat[24], 3'b000, fs_err | sd_err, mounted};
endmodule
`default_nettype wire
