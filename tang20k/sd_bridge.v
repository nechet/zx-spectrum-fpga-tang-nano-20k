// -----------------------------------------------------------------------------
// SD loader interface on the board's 8255 (КР580ВВ55): the FPGA plays an
// off-board peripheral plugged into the 8255's port pins, as a 1980s disk
// interface would sit on an edge connector.
//
// The Z80 programs the 8255 with mode word 91h (port A in, port B out, port
// C upper out, port C lower in) and then talks one byte at a time:
//
//   port 3F (B, out)   command byte
//   port 5F (C) bit 4  STROBE, Z80 -> here: toggled for every request
//   port 5F (C) bit 0  ACK, here -> Z80: made equal to STROBE when the
//                      answer is ready
//   port 1F (A, in)    answer byte
//
// Toggles rather than pulses, so neither side needs a timed pulse -- which
// matters here, because this side runs on the board's 27 MHz clock and the
// Z80 side on 135 MHz.  Each signal crossing over is synchronised (two
// flip-flops); the command byte and the answer byte are stable long before
// the toggle that announces them.
//
// Commands and answers:
//   01 mount             00 ok, 8x error (x = fat32 / sd_spi code)
//   02 first, 03 next    00 a game is ready to read, 01 no more games, 8x error
//   04 open              00 (the game found by the last first/next)
//   05 read              next byte: after first/next the 15-byte entry
//                        (11-char 8.3 name, then size, low byte first);
//                        after open, the file's bytes (00 past the end)
//   06 tape?             00 if a .TAP is inserted (07), 01 if not
//   07 insert tape       00; the open file is a tape: the ROM's LD-BYTES
//                        reads its blocks (sdmenu.asm, tapld).  Mount,
//                        first and next take it out again.
//   other                FF
// -----------------------------------------------------------------------------
`default_nettype none

module sd_bridge #(
    parameter integer CLK_HZ  = 27_000_000,
    parameter integer SLOW_HZ = 400_000
) (
    input  wire       clk,          // 27 MHz: the card side
    input  wire       clk_sys,      // the board's clock, for the answer side
    // the 8255's port pins, as the board shows them (clk_sys domain)
    input  wire [7:0] pb,           // command
    input  wire       strobe,       // PC4
    output reg  [7:0] pa_ext = 8'hFF,   // answer, onto port A
    output reg        ack_ext = 1'b0,   // onto PC0
    // the card
    output wire       sd_sck, sd_cs_n, sd_mosi,
    input  wire       sd_miso,
    // status, for LEDs
    output wire       mounted,
    output wire       error
);
  // --- the card and its filesystem -------------------------------------------
  reg  sd_start = 1'b0;
  wire sd_rd, sd_ready, sd_err, sd_dvalid, sdhc; wire [31:0] sd_lba; wire [7:0] sd_dout; wire [3:0] sd_ec;
  sd_spi #(.CLK_HZ(CLK_HZ), .SLOW_HZ(SLOW_HZ), .FAST_HALF(1)) sd (
      .clk(clk), .start(sd_start), .sd_sck(sd_sck), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi),
      .sd_miso(sd_miso), .rd(sd_rd), .lba(sd_lba), .dout(sd_dout), .dout_valid(sd_dvalid),
      .ready(sd_ready), .err(sd_err), .err_code(sd_ec), .sdhc(sdhc));

  reg fs_mount = 1'b0, fs_first = 1'b0, fs_next = 1'b0, fs_open = 1'b0, fs_take = 1'b0;
  wire fs_busy, fs_err, ent_valid, dir_end, dvalid, eof; wire [3:0] fs_ec;
  wire [87:0] ent_name; wire [31:0] ent_size, ent_clus; wire [7:0] fs_dout;
  fat32 fs (.clk(clk), .mount(fs_mount), .first(fs_first), .next(fs_next), .open(fs_open),
      .open_clus(ent_clus), .open_size(ent_size), .busy(fs_busy), .mounted(mounted),
      .err(fs_err), .err_code(fs_ec), .ent_valid(ent_valid), .dir_end(dir_end),
      .ent_name(ent_name), .ent_size(ent_size), .ent_clus(ent_clus),
      .dout(fs_dout), .dvalid(dvalid), .eof(eof), .take(fs_take),
      .sd_rd(sd_rd), .sd_lba(sd_lba), .sd_dout(sd_dout), .sd_dvalid(sd_dvalid),
      .sd_ready(sd_ready), .sd_err(sd_err));
  assign error = fs_err | sd_err;

  // --- from the Z80 side -------------------------------------------------------
  reg [2:0] st_s = 3'b000;          // STROBE: two flip-flops, then edge memory
  reg [7:0] pb_s1 = 8'h00, pb_s2 = 8'h00;
  always @(posedge clk) begin
    st_s  <= {st_s[1:0], strobe};
    pb_s1 <= pb; pb_s2 <= pb_s1;
  end
  wire request = st_s[2] ^ st_s[1];

  // --- the answer, crossing back -------------------------------------------------
  reg [7:0] answer = 8'hFF;
  reg       ack = 1'b0;
  reg [1:0] ack_s = 2'b00;
  always @(posedge clk_sys) begin
    pa_ext <= answer;               // stable well before ack changes
    ack_s  <= {ack_s[0], ack};
    ack_ext <= ack_s[1];
  end

  // --- the command sequencer -----------------------------------------------------
  localparam [3:0] B_IDLE = 4'd0, B_GO = 4'd1, B_SDW = 4'd2, B_ACKW = 4'd3, B_MNTW = 4'd4,
                   B_DIRW = 4'd5, B_READ = 4'd6, B_TAKE = 4'd7, B_ANS = 4'd8, B_ANS2 = 4'd9,
                   B_GAP = 4'd10;
  reg [3:0]  b = B_IDLE, b_after = B_IDLE;
  reg [7:0]  cmd = 8'h00;
  reg [3:0]  rec_pos = 4'd0;        // 0..14: entry bytes; 15 = streaming the file
  reg        want_strobe = 1'b0;    // the STROBE level being answered
  reg [7:0]  gap = 8'd0;
  reg        tape = 1'b0;           // a .TAP is inserted (07)

  // byte k of the 15-byte entry record
  function [7:0] rec(input [3:0] k);
    case (k)
      4'd0: rec = ent_name[87:80];  4'd1: rec = ent_name[79:72];  4'd2: rec = ent_name[71:64];
      4'd3: rec = ent_name[63:56];  4'd4: rec = ent_name[55:48];  4'd5: rec = ent_name[47:40];
      4'd6: rec = ent_name[39:32];  4'd7: rec = ent_name[31:24];  4'd8: rec = ent_name[23:16];
      4'd9: rec = ent_name[15:8];   4'd10: rec = ent_name[7:0];
      4'd11: rec = ent_size[7:0];   4'd12: rec = ent_size[15:8];  4'd13: rec = ent_size[23:16];
      default: rec = ent_size[31:24];
    endcase
  endfunction

  task reply(input [7:0] v); begin answer <= v; b <= B_ANS; end endtask
  // Wait a few clocks (fs/sd outputs settle after a command pulse), then go on
  task after(input [3:0] nxt); begin gap <= 8'd3; b_after <= nxt; b <= B_GAP; end endtask

  always @(posedge clk) begin
    sd_start <= 1'b0; fs_mount <= 1'b0; fs_first <= 1'b0; fs_next <= 1'b0;
    fs_open <= 1'b0; fs_take <= 1'b0;
    case (b)
      B_IDLE:  if (request) begin want_strobe <= st_s[1]; cmd <= pb_s2; b <= B_GO; end
      B_GO:    case (cmd)
                 8'h01: begin sd_start <= 1'b1; tape <= 1'b0; after(B_SDW); end
                 8'h02: begin fs_first <= 1'b1; tape <= 1'b0; rec_pos <= 4'd0; after(B_DIRW); end
                 8'h03: begin fs_next  <= 1'b1; tape <= 1'b0; rec_pos <= 4'd0; after(B_DIRW); end
                 8'h04: begin fs_open  <= 1'b1; rec_pos <= 4'd15; after(B_ANS2); end
                 8'h05: b <= B_READ;
                 8'h06: reply(tape ? 8'h00 : 8'h01);
                 8'h07: begin tape <= 1'b1; reply(8'h00); end
                 default: reply(8'hFF);
               endcase
      B_GAP:   if (gap == 8'd0) b <= b_after; else gap <= gap - 8'd1;
      // mount: card first, then the filesystem
      B_SDW:   if (sd_err) reply({4'h8, sd_ec});
               else if (sd_ready) begin fs_mount <= 1'b1; after(B_MNTW); end
      B_MNTW:  if (!fs_busy) reply(mounted ? 8'h00 : {4'h8, fs_ec});
      B_DIRW:  if (!fs_busy) reply(ent_valid ? 8'h00 : dir_end ? 8'h01 : {4'h8, fs_ec});
      B_ANS2:  if (!fs_busy) reply(fs_err ? {4'h8, fs_ec} : 8'h00);
      // read: an entry byte, or the next file byte once it is in front of us
      B_READ:  if (rec_pos != 4'd15) begin
                 reply(rec(rec_pos)); if (rec_pos != 4'd14) rec_pos <= rec_pos + 4'd1;
               end else if (dvalid) begin
                 answer <= fs_dout; fs_take <= 1'b1; b <= B_TAKE;
               end else if (eof || fs_err || !mounted) reply(8'h00);
      B_TAKE:  b <= B_ANS;
      // answer: the byte is on port A first, then ACK follows STROBE
      B_ANS:   begin gap <= 8'd4; b <= B_ACKW; end
      B_ACKW:  if (gap == 8'd0) begin ack <= want_strobe; b <= B_IDLE; end
               else gap <= gap - 8'd1;
      default: b <= B_IDLE;
    endcase
  end
endmodule
`default_nettype wire
