// -----------------------------------------------------------------------------
// FAT32 reader: finds the games in the root folder of a microSD card and
// streams a chosen file, byte by byte.  Sits on top of sd_spi.v.
//
// FAT32 in one paragraph.  The card's first sector (MBR) lists partitions;
// ours is type 0B/0C at sector P.  The partition's first sector (boot sector)
// gives the geometry: R reserved sectors, then N copies of the FAT (F sectors
// each), then the data area, cut into clusters of S sectors numbered from 2.
// A folder is a file of 32-byte entries: 8+3 name, attributes, first cluster,
// size.  A file's clusters form a linked list in the FAT -- entry c holds the
// number of the cluster after c (>= 0FFFFFF8 = end).  So, all counting:
//
//   FAT sector of cluster c   P + R + c / 128        (128 entries per sector)
//   first sector of cluster c P + R + N*F + (c - 2) * S
//
// The FAT is the card's "next address" ROM: like a microprogram sequencer
// whose next-address field is looked up, not counted.
//
// One 512-byte buffer holds the last sector read, tagged with its number, so
// listing the folder and reading a file can interleave freely -- a sector is
// re-read only when the one needed is not the one in the buffer.
//
// Interface (pulse a command while !busy):
//   mount              read MBR + boot sector             -> mounted or err
//   first / next       find the first / next game file    -> ent_* valid, or dir_end
//   open               start streaming file (open_clus, open_size)
//   take               with dvalid: consume dout; eof when the file is done
// Only short (8.3) names are read; .Z80 .SNA .TAP files are listed.
// -----------------------------------------------------------------------------
`default_nettype none

module fat32 (
    input  wire        clk,
    // commands
    input  wire        mount, first, next, open,
    input  wire [31:0] open_clus, open_size,
    output wire        busy,
    output reg         mounted = 1'b0,
    output reg         err = 1'b0,
    output reg  [3:0]  err_code = 4'h0,
    // directory entry
    output reg         ent_valid = 1'b0,
    output reg         dir_end = 1'b0,
    output reg  [87:0] ent_name = 88'd0,     // 11 chars, first char in [87:80]
    output reg  [31:0] ent_size = 32'd0,
    output reg  [31:0] ent_clus = 32'd0,
    // file stream: dout is valid while dvalid; pulse take to move on
    output wire [7:0]  dout,
    output wire        dvalid,
    output reg         eof = 1'b0,
    input  wire        take,
    // to sd_spi
    output reg         sd_rd = 1'b0,
    output reg  [31:0] sd_lba = 32'd0,
    input  wire [7:0]  sd_dout,
    input  wire        sd_dvalid,
    input  wire        sd_ready,
    input  wire        sd_err
);
  // --- sector buffer ---------------------------------------------------------
  reg  [7:0] mem [0:511];
  reg  [8:0] wa = 9'd0;
  reg  [8:0] ra = 9'd0;
  reg  [7:0] rb = 8'h00;
  always @(posedge clk) begin
    if (sd_rd) wa <= 9'd0;
    else if (sd_dvalid) begin mem[wa] <= sd_dout; wa <= wa + 9'd1; end
    rb <= mem[ra];
  end
  reg        buf_ok = 1'b0;          // buffer holds sector buf_lba
  reg [31:0] buf_lba = 32'd0;

  // --- geometry ----------------------------------------------------------------
  reg [31:0] part = 32'd0, fat_lba = 32'd0, data_lba = 32'd0, root = 32'd0;
  reg [7:0]  nfats = 8'd2;
  reg [2:0]  spc_log2 = 3'd0;
  wire [7:0] spc_last = (8'd1 << spc_log2) - 8'd1;   // last sector number in a cluster

  // --- states ------------------------------------------------------------------
  localparam [4:0]
    S_IDLE  = 5'd0,  S_LOAD  = 5'd1,  S_LOADW = 5'd2,  S_GRAB  = 5'd3,
    S_M0    = 5'd4,  S_M1    = 5'd5,  S_M2    = 5'd6,  S_M3    = 5'd7,  S_M4 = 5'd8,
    S_M5    = 5'd9,  S_M6    = 5'd10,
    S_DSCAN = 5'd11, S_DENT  = 5'd12, S_DCHK  = 5'd13, S_DADV  = 5'd14, S_DFAT = 5'd15,
    S_FLOAD = 5'd16, S_FWAIT = 5'd17, S_FOUT  = 5'd18, S_FFAT  = 5'd19,
    S_NEXT  = 5'd20, S_NEXTW = 5'd21, S_NEXTV = 5'd22, S_FAIL  = 5'd23,
    S_L0    = 5'd24, S_L1    = 5'd25, S_L2    = 5'd26, S_L3    = 5'd27;
  reg [4:0]   st = S_IDLE;
  reg [4:0]   gret = S_IDLE;          // where a grab returns
  reg [4:0]   lret = S_IDLE;          // where a load returns
  reg [4:0]   cret = S_IDLE;          // where a cluster-chain lookup returns
  reg [255:0] grab = 256'd0;          // bytes read from the buffer, newest at the top
  reg [5:0]   gn = 6'd0;              // bytes left to grab
  reg [1:0]   gph = 2'd0;             // buffer read pipeline step
  reg [31:0]  want = 32'd0;           // sector to load
  reg [31:0]  d_clus = 32'd0;         // folder walk
  reg [7:0]   d_sec = 8'd0;
  reg [3:0]   d_ent = 4'd0;
  reg [31:0]  f_clus = 32'd0, f_left = 32'd0;   // file stream
  reg [7:0]   f_sec = 8'd0;
  reg [8:0]   f_off = 9'd0;
  reg [31:0]  c_in = 32'd0;           // cluster-chain lookup: in, then out
  reg [31:0]  lc = 32'd0;             // sector-number pipeline
  reg         hit = 1'b0;             // wanted sector is in the buffer
  reg [7:0]   ls = 8'd0;
  reg [4:0]   pret = S_IDLE;          // where a sector-number calculation goes on to load

  wire cmd_ok = (st == S_IDLE) || (st == S_FOUT) || (st == S_FAIL);
  assign busy   = !cmd_ok;
  assign dvalid = (st == S_FOUT);
  assign dout   = rb;

  // After a grab of n bytes, byte k of them is grab[256 - 8n + 8k +: 8].
  // grab n bytes from buffer offset o, then go to r
  task do_grab(input [8:0] o, input [5:0] n, input [4:0] r);
    begin ra <= o; gn <= n; gph <= 2'd0; gret <= r; st <= S_GRAB; end
  endtask
  // make sector l the buffer's content, then go to r
  task do_load(input [31:0] l, input [4:0] r);
    begin want <= l; lret <= r; gph <= 2'd0; st <= S_LOAD; end
  endtask
  // load sector s of cluster c, then go to r.  The sector number,
  //   data_lba + (c - 2) * sectors_per_cluster + s,
  // is worked out over four clocks, one operation each (S_L0..S_L3): done in
  // one clock it is a chain of three adders and a shifter, 14 ns, and at
  // 135 MHz (7.4 ns) the hardware got garbage -- in simulation, which has no
  // gate delays, it worked.
  task do_clus(input [31:0] c, input [7:0] s, input [4:0] r);
    begin lc <= c; ls <= s; pret <= r; st <= S_L0; end
  endtask
  // the cluster after c (from the FAT) into c_in, then go to r
  task do_next(input [31:0] c, input [4:0] r);
    begin c_in <= c; cret <= r; st <= S_NEXT; end
  endtask
  task fail(input [3:0] code);
    begin err <= 1'b1; err_code <= code; mounted <= 1'b0; st <= S_FAIL; end
  endtask

  // the 32-byte folder entry just grabbed
  wire [7:0]  e0   = grab[7:0];
  wire [7:0]  attr = grab[8*11 +: 8];
  wire [23:0] ext  = {grab[8*8 +: 8], grab[8*9 +: 8], grab[8*10 +: 8]};
  wire        game = (ext == "Z80") || (ext == "SNA") || (ext == "TAP");
  // 8 bytes grabbed, as a string (first byte leftmost)
  wire [63:0] str8 = {grab[192 +: 8], grab[200 +: 8], grab[208 +: 8], grab[216 +: 8],
                      grab[224 +: 8], grab[232 +: 8], grab[240 +: 8], grab[248 +: 8]};

  always @(posedge clk) begin
    sd_rd <= 1'b0;

    if (cmd_ok && mount) begin
      err <= 1'b0; err_code <= 4'h0; mounted <= 1'b0; buf_ok <= 1'b0;
      ent_valid <= 1'b0; dir_end <= 1'b0; eof <= 1'b0;
      do_load(32'd0, S_M0);
    end else if (cmd_ok && mounted && first) begin
      ent_valid <= 1'b0; dir_end <= 1'b0;
      d_clus <= root; d_sec <= 8'd0; d_ent <= 4'd0; st <= S_DSCAN;
    end else if (cmd_ok && mounted && next && ent_valid) begin
      ent_valid <= 1'b0; st <= S_DADV;
    end else if (cmd_ok && mounted && open) begin
      f_clus <= open_clus; f_left <= open_size; f_sec <= 8'd0; f_off <= 9'd0;
      eof <= (open_size == 32'd0); st <= (open_size == 32'd0) ? S_IDLE : S_FLOAD;
    end else case (st)
      S_IDLE, S_FAIL: ;

      // --- helpers ---------------------------------------------------------------
      // The 32-bit "already in the buffer?" compare gets a clock of its own
      // (hit), for timing: compare and act in one clock missed 135 MHz.
      S_LOAD:  if (!gph[0]) begin hit <= buf_ok && (buf_lba == want); gph <= 2'd1; end
               else if (hit) begin gph <= 2'd0; st <= lret; end
               else if (sd_err) begin gph <= 2'd0; fail(4'h1); end
               else if (sd_ready) begin gph <= 2'd0; sd_lba <= want; sd_rd <= 1'b1; buf_ok <= 1'b0; st <= S_LOADW; end
      S_LOADW: if (sd_err) fail(4'h1);
               else if (sd_ready && !sd_rd) begin buf_ok <= 1'b1; buf_lba <= want; st <= lret; end
      // rb follows ra one clock behind: set ra, wait a clock, take rb, step ra
      S_GRAB:  if (gph == 2'd0) gph <= 2'd1;
               else begin
                 grab <= {rb, grab[255:8]}; ra <= ra + 9'd1; gph <= 2'd0; gn <= gn - 6'd1;
                 if (gn == 6'd1) st <= gret;
               end
      S_NEXT:  do_load(fat_lba + {7'd0, c_in[31:7]}, S_NEXTW);
      S_NEXTW: do_grab({c_in[6:0], 2'b00}, 6'd4, S_NEXTV);
      S_NEXTV: begin c_in <= {4'h0, grab[251:224]}; st <= cret; end
      S_L0:    begin lc <= lc - 32'd2;            st <= S_L1; end
      S_L1:    begin lc <= lc << spc_log2;        st <= S_L2; end
      S_L2:    begin lc <= lc + data_lba;         st <= S_L3; end
      S_L3:    do_load(lc + {24'd0, ls}, pret);

      // --- mount -------------------------------------------------------------------
      S_M0: do_grab(9'h1C2, 6'd8, S_M1);                    // type at 1C2, start at 1C6
      S_M1: if (grab[199:192] == 8'h0B || grab[199:192] == 8'h0C) begin
              part <= grab[255:224]; do_load(grab[255:224], S_M3);
            end else do_grab(9'h052, 6'd8, S_M2);           // no MBR: FAT32 from sector 0?
      S_M2: if (str8 == "FAT32   ") begin part <= 32'd0; st <= S_M3; end
            else fail(4'h2);                                // no FAT32 found
      S_M3: do_grab(9'h00B, 6'd6, S_M4);                    // 0B..10
      S_M4: if (grab[223:208] != 16'h0200) fail(4'h3);      // bytes/sector: 512 only
            else begin
              case (grab[231:224])                          // sectors per cluster
                8'd1: spc_log2 <= 3'd0;  8'd2: spc_log2 <= 3'd1;  8'd4: spc_log2 <= 3'd2;
                8'd8: spc_log2 <= 3'd3;  8'd16: spc_log2 <= 3'd4; 8'd32: spc_log2 <= 3'd5;
                8'd64: spc_log2 <= 3'd6; default: spc_log2 <= 3'd7;
              endcase
              fat_lba <= part + {16'd0, grab[247:232]};     // + reserved sectors
              nfats   <= grab[255:248];
              do_grab(9'h024, 6'd4, S_M5);                  // FAT size
            end
      S_M5: begin
              data_lba <= fat_lba + ((nfats == 8'd1) ? grab[255:224] : {grab[254:224], 1'b0});
              do_grab(9'h02C, 6'd4, S_M6);                  // root cluster
            end
      S_M6: begin root <= grab[255:224]; mounted <= 1'b1; st <= S_IDLE; end

      // --- folder walk ---------------------------------------------------------------
      S_DSCAN: do_clus(d_clus, d_sec, S_DENT);
      S_DENT:  do_grab({d_ent, 5'd0}, 6'd32, S_DCHK);
      S_DCHK:  if (e0 == 8'h00) begin dir_end <= 1'b1; st <= S_IDLE; end   // end of folder
               else if (e0 == 8'hE5 || attr[3] || attr[4] || !game) st <= S_DADV;
               else begin                                   // (LFN pieces have attr bit 3 set)
                 ent_name  <= {grab[7:0], grab[15:8], grab[23:16], grab[31:24], grab[39:32],
                               grab[47:40], grab[55:48], grab[63:56], grab[71:64], grab[79:72], grab[87:80]};
                 ent_clus  <= {grab[8*21 +: 8], grab[8*20 +: 8], grab[8*27 +: 8], grab[8*26 +: 8]};
                 ent_size  <= grab[8*28 +: 32];
                 ent_valid <= 1'b1; st <= S_IDLE;
               end
      S_DADV:  begin
                 d_ent <= d_ent + 4'd1;
                 // Back through S_DSCAN, not straight to S_DENT: a file read in
                 // between may have replaced the folder sector in the buffer
                 // (S_LOAD returns at once when it is still there).
                 if (d_ent != 4'd15) st <= S_DSCAN;
                 else if (d_sec != spc_last) begin d_sec <= d_sec + 8'd1; st <= S_DSCAN; end
                 else begin d_sec <= 8'd0; do_next(d_clus, S_DFAT); end
               end
      S_DFAT:  if (c_in >= 32'h0FFF_FFF8 || c_in < 32'd2) begin dir_end <= 1'b1; st <= S_IDLE; end
               else begin d_clus <= c_in; st <= S_DSCAN; end

      // --- file stream ---------------------------------------------------------------
      S_FLOAD: do_clus(f_clus, f_sec, S_FWAIT);
      S_FWAIT: begin                                        // point ra, let rb catch up
                 ra <= f_off; gph <= gph + 2'd1;
                 if (gph == 2'd2) begin gph <= 2'd0; st <= S_FOUT; end
               end
      S_FOUT:  if (take) begin
                 f_left <= f_left - 32'd1; f_off <= f_off + 9'd1;
                 if (f_left == 32'd1) begin eof <= 1'b1; st <= S_IDLE; end
                 else if (f_off != 9'd511) st <= S_FWAIT;
                 else if (f_sec != spc_last) begin f_sec <= f_sec + 8'd1; st <= S_FLOAD; end
                 else begin f_sec <= 8'd0; do_next(f_clus, S_FFAT); end
               end
      S_FFAT:  if (c_in >= 32'h0FFF_FFF8 || c_in < 32'd2) fail(4'h4);   // chain ended early
               else begin f_clus <= c_in; st <= S_FLOAD; end
      default: st <= S_IDLE;
    endcase
  end
endmodule
`default_nettype wire
