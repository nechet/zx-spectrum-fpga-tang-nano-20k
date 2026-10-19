// Integration test of the SD loader menu (step 3): the whole board, the
// patched ROM (spectrum48_sd.hex), sd_bridge on the 8255, and the card model
// with mk_fat_image.py's image.  "Presses" F12 over PS/2, lets the menu list
// the games, reads the screen back by matching every 8x8 cell against the
// ROM font, then presses 6 (down) and ENTER and checks the bottom line.
// Then 7 (up) and ENTER on JETPAC.Z80 -- mk_testz80.py's test snapshot: every
// byte the loader writes is checked against the image it should leave, and
// the snapshot's own program checks its registers and shows green or red.
//
// Built from ../core (see tb_sdmenu.sh).
`timescale 1ns / 1fs

module tb_sdmenu;
  reg clk = 1'b0, rst_i = 1'b0;
  always #18.518518 clk = ~clk;
  wire [5:0] led;
  wire tmds_clk_p, tmds_clk_n; wire [2:0] tmds_d_p, tmds_d_n;
  reg  ps2_clk = 1'b1, ps2_data = 1'b1;
  wire sd_clk, sd_cmd, sd_dat3, sd_dat0;
  top #(.WITH_HDMI(0)) dut (.clk(clk), .rst_i(rst_i), .led(led),
           .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
           .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
           .ps2_clk(ps2_clk), .ps2_data(ps2_data),
           .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat3(sd_dat3), .sd_dat0(sd_dat0),
           .nmi_btn(1'b0));
`ifndef SD_IMAGE
`define SD_IMAGE "../tang20k/tb_fat_image.hex"
`define SD_SECTORS 512
`endif
  sd_card_model #(.IMAGE(`SD_IMAGE), .SECTORS(`SD_SECTORS)) card (
      .sck(sd_clk), .cs_n(sd_dat3), .mosi(sd_cmd), .miso(sd_dat0));

  // --- PS/2 keyboard ---------------------------------------------------------
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
  task tap(input [7:0] code);             // press, hold 30 ms, release
    begin send_byte(code); #30_000_000; send_byte(8'hF0); send_byte(code); end
  endtask

  // --- screen: rebuilt from the CPU's writes, read back with the ROM font ----
  reg [7:0] scr [0:6143];
  reg [7:0] atr [0:767];
  // the loader's writes, and what they should come to
  reg [7:0] wmem [0:49151];
  reg [7:0] zmem [0:49151];
  reg loading = 1'b0;
  integer fails = 0, i;
  reg [7:0] rom [0:16383];
  initial $readmemh("../tang20k/spectrum48_sd.hex", rom);
  wire [15:0] ca = dut.kras.U_D1.a;
  wire [7:0]  cdo = dut.kras.U_D1.dout;
  wire mreq_n = dut.kras.U_D1.mreq_n, wr_n = dut.kras.U_D1.wr_n;
  reg  wr_d = 1'b1;
  always @(posedge dut.clk_x5) begin
    wr_d <= wr_n;
    if (!mreq_n && !wr_n && wr_d && ca >= 16'h4000 && ca < 16'h5800) scr[ca - 16'h4000] <= cdo;
    if (!mreq_n && !wr_n && wr_d && ca >= 16'h5800 && ca < 16'h5B00) atr[ca - 16'h5800] <= cdo;
    if (!mreq_n && !wr_n && wr_d && ca >= 16'h4000 && loading) wmem[ca - 16'h4000] <= cdo;
  end
  initial $readmemh("../tang20k/tb_testz80_mem.hex", zmem);
`ifdef TRACE_M1
  // debug: opcode fetches in the doorway area and the first ones above 4000,
  // and a PC sample every 50 ms, once loading has started
  reg m1_d = 1'b1; integer nhi = 0; reg [15:0] lastpc;
  always @(posedge dut.clk_x5) begin
    m1_d <= dut.kras.U_D1.m1_n;
    if (!dut.kras.U_D1.m1_n && m1_d) begin
      lastpc = ca;
      if (loading && ((ca >= 16'h3860 && ca < 16'h38B0) || ca < 16'h0100 || (ca >= 16'h4000 && nhi < 60))) begin
        $display("M1 %h bank %b at %0d us", ca, dut.rom_bank, $time / 1_000);
        if (ca >= 16'h4000) nhi = nhi + 1;
      end
    end
  end
  always begin #50_000_000; if (loading) $display("pc %h bank %b at %0d ms", lastpc, dut.rom_bank, $time / 1_000_000); end
  initial begin #600_000_000; $display("TRACE STOP"); show_screen; for (i = 2; i < 8; i = i + 1) $display("attr row %0d: %h", i, atr[i*32]); $finish; end
`endif
`ifdef GAME_TAP
  reg g_m1d = 1'b1, game_ran = 1'b0; reg [15:0] game_pc = 16'h0000;
  always @(posedge dut.clk_x5) begin
    g_m1d <= dut.kras.U_D1.m1_n;
    if (!dut.kras.U_D1.m1_n && g_m1d) begin
      game_pc <= ca;
      if (ca == `GAME_PC) game_ran <= 1'b1;
    end
  end
`endif
  wire [3:0] bd = dut.kras.U_D61.q;        // {VBD1, tape, VBD2, VBD0}
  wire [2:0] grb = {bd[1], bd[3], bd[0]};  // green, red, blue
  // every colour byte of row r, as the CPU wrote it, must be w
  task expect_attr(input integer r, input [7:0] w);
    integer c, bad;
    begin
      bad = 0;
      for (c = 0; c < 32; c = c + 1) if (atr[r*32 + c] !== w) bad = bad + 1;
      if (bad == 0) $display("PASS  attr row %0d: %h", r, w);
      else begin
        $display("FAIL  attr row %0d: %h %h .. %h, want %h", r, atr[r*32], atr[r*32+1], atr[r*32+31], w);
        fails = fails + 1;
      end
    end
  endtask

  // --- the picture the video hardware actually makes, as a PPM ---------------
`ifdef HDMI_720P
  localparam integer H_ACTIVE = 1280, V_ACTIVE = 720;
`else
  localparam integer H_ACTIVE = 720, V_ACTIVE = 576;
`endif
  reg grab = 1'b0, capturing = 1'b0, vs_d = 1'b0;
  reg [3:0] fb [0:H_ACTIVE*V_ACTIVE-1];
  integer px_n = 0, fh;
  always @(posedge dut.clk_pixel) begin
    vs_d <= dut.dbl_vsync;
    if (grab && !capturing && !vs_d && dut.dbl_vsync) begin capturing <= 1'b1; px_n = 0; end
    if (capturing && dut.dbl_active && dut.ox < H_ACTIVE && dut.oy < V_ACTIVE) begin
      fb[dut.oy * H_ACTIVE + dut.ox] = dut.rgbi;
      px_n = px_n + 1;
    end
    if (capturing && px_n >= H_ACTIVE * V_ACTIVE) begin capturing <= 1'b0; grab <= 1'b0; end
  end
  task frame(input [8*16-1:0] name);
    integer x, y; reg [3:0] c; reg [7:0] lvl;
    begin
      grab = 1'b1; wait (capturing); wait (!capturing);
      fh = $fopen(name, "w");
      $fdisplay(fh, "P3\n%0d %0d\n255", H_ACTIVE, V_ACTIVE);
      for (y = 0; y < V_ACTIVE; y = y + 1)
        for (x = 0; x < H_ACTIVE; x = x + 1) begin
          c = fb[y * H_ACTIVE + x]; lvl = c[3] ? 8'hFF : 8'hCD;
          $fdisplay(fh, "%0d %0d %0d", c[2] ? lvl : 0, c[1] ? lvl : 0, c[0] ? lvl : 0);
        end
      $fclose(fh);
      $display("wrote %0s", name);
    end
  endtask

`ifdef HDMI_720P
  // The captured 720p frame against what the CPU wrote: every pixel of the
  // paper from scr/atr (ink or paper, bright), and every pixel around it --
  // the 24 border lines above and below, the side borders and the 16:9
  // extensions -- the border colour.  3 x 3 screen pixels a Spectrum pixel;
  // the paper is centred: its top-left at (256, 72).  The tripler stores the
  // board's window from pixel 0, the paper starting at its pixel PAPER_X.
  task check_frame;
    integer x, y, sx, sy, bad; reg [7:0] a8, bits; reg [12:0] a; reg [3:0] want, ink, pap;
    begin
      bad = 0;
      for (y = 0; y < V_ACTIVE; y = y + 1)
        for (x = 0; x < H_ACTIVE; x = x + 1) begin
          sx = (x < dut.dbl.H_PAD) ? -dut.dbl.PAPER_X :
               ((x - dut.dbl.H_PAD) / 3 > 351 ? 351 - dut.dbl.PAPER_X : (x - dut.dbl.H_PAD) / 3 - dut.dbl.PAPER_X);
          sy = y / 3 - 24;
          if (sx >= 0 && sx < 256 && sy >= 0 && sy < 192) begin
            a    = ((sy & 8'hC0) << 5) | ((sy & 7) << 8) | ((sy & 8'h38) << 2) | (sx >> 3);
            bits = scr[a];
            a8   = atr[(sy >> 3) * 32 + (sx >> 3)];
            ink  = {a8[6], a8[1], a8[2], a8[0]};        // {bright, R, G, B}
            pap  = {a8[6], a8[4], a8[5], a8[3]};
            want = bits[7 - (sx & 7)] ? ink : pap;
          end else
            want = {1'b0, grb[1], grb[2], grb[0]};      // grb is {G, R, B}
          if (fb[y * H_ACTIVE + x] !== want) begin
            if (bad < 6) $display("FAIL  pixel (%0d, %0d): %h, want %h", x, y, fb[y * H_ACTIVE + x], want);
            bad = bad + 1;
          end
        end
      if (bad == 0) $display("PASS  720p frame: all 1280 x 720 pixels match the screen memory and border");
      else begin $display("FAIL  720p frame: %0d pixels wrong", bad); fails = fails + 1; end
    end
  endtask
`endif

  function [7:0] ocr(input integer r, input integer c);
    integer ch, k, ok; reg [12:0] a;
    begin
      ocr = "~";
      for (ch = 32; ch < 128; ch = ch + 1) begin
        ok = 1;
        for (k = 0; k < 8; k = k + 1) begin
          a = ((r & 24) << 8) | ((r & 7) << 5) | c | (k << 8);
          if (scr[a] !== rom[16'h3C00 + ch * 8 + k]) ok = 0;
        end
        if (ok) begin ocr = ch; ch = 128; end
      end
    end
  endfunction
  reg [8*32-1:0] line;
  task show_row(input integer r);
    integer c;
    begin
      for (c = 0; c < 32; c = c + 1) line[8*(31 - c) +: 8] = ocr(r, c);
      $display("  |%s|", line);
    end
  endtask
  task show_screen;
    integer r;
    begin for (r = 0; r < 24; r = r + 1) show_row(r); end
  endtask

  reg [8*32-1:0] want;
  task expect_row(input integer r, input [8*32-1:0] w);
    integer c;
    begin
      for (c = 0; c < 32; c = c + 1) line[8*(31 - c) +: 8] = ocr(r, c);
      if (line == w) $display("PASS  row %0d: |%s|", r, line);
      else begin $display("FAIL  row %0d: |%s|, want |%s|", r, line, w); fails = fails + 1; end
    end
  endtask
  // wait (polling the screen every 2 ms) until row r reads w
  task wait_row(input integer r, input [8*32-1:0] w);
    integer c, n;
    begin
      n = 0; line = 0;
      while (line != w && n < 150) begin
        #2_000_000 n = n + 1;
        for (c = 0; c < 32; c = c + 1) line[8*(31 - c) +: 8] = ocr(r, c);
      end
    end
  endtask

  // wait (polling every 10 ms, up to ms_max) until row r reads w
  task wait_long(input integer r, input [8*32-1:0] w, input integer ms_max);
    integer c, n;
    begin
      n = 0; line = 0;
      while (line != w && n < ms_max / 10) begin
        #10_000_000 n = n + 1;
        for (c = 0; c < 32; c = c + 1) line[8*(31 - c) +: 8] = ocr(r, c);
      end
    end
  endtask

  // wait (polling every 1 ms, up to 500 ms) for the selection bar on row r:
  // the menu draws it just before it reads the keyboard, so a key sent before
  // that -- while a page is still being read from the card -- would be lost
  task wait_bar(input integer r);
    integer n;
    begin
      n = 0;
      while (atr[r*32] !== 8'h68 && n < 500) begin #1_000_000 n = n + 1; end
      if (n == 500) begin $display("FAIL  no bar on row %0d", r); fails = fails + 1; end
    end
  endtask
  task key_at(input integer r, input [7:0] code);   // a key, once the menu listens
    begin wait_bar(r); #5_000_000; tap(code); end
  endtask

  initial begin
    for (i = 0; i < 6144; i = i + 1) scr[i] = 8'h00;
    #40_000_000 rst_i = 1'b1;              // release the CPU after the board reset
`ifdef TAP_TEST
    // --- the .TAP loader: from BASIC, as a user would -------------------------
    // TINY.TAP is mk_testtap.py's tape.  Wait for the ROM to finish its memory
    // test and show the copyright line, then F12 and ENTER on the tape: the
    // menu starts BASIC afresh and runs LOAD "" by itself.  Wait for the
    // tape's program to show green (or red).
    wait_long(23, {8'h7F, " 1982 Sinclair Research Ltd    "}, 3000);
    expect_row(23, {8'h7F, " 1982 Sinclair Research Ltd    "});
    $display("BASIC ready at %0d ms; F12", $time / 1_000_000);
    send_byte(8'h07); #30_000_000; send_byte(8'hF0); send_byte(8'h07);
    key_at(2, 8'h36); key_at(3, 8'h36); key_at(4, 8'h36);   // down three times: TINY.TAP
    key_at(5, 8'h5A);                      // ENTER: inserts it and runs LOAD "" itself
    $display("ENTER on the tape at %0d ms", $time / 1_000_000);
`ifdef GAME_TAP
    // a real game in TINY.TAP's place (tb_sdgame.sh): pass when the CPU
    // fetches an opcode at the game's entry point, GAME_PC
    begin : game
      integer t0; t0 = $time / 1_000_000;
      while (!game_ran && $time / 1_000_000 < t0 + 8000) begin
        #250_000_000;
        $display("  %0d ms: last M1 %h, bank %b, border %b", $time / 1_000_000, game_pc, dut.rom_bank, grb);
      end
      show_screen;
      if (game_ran) $display("PASS  game entered at %h, %0d ms", `GAME_PC, $time / 1_000_000);
      else begin $display("FAIL  game not entered"); fails = fails + 1; end
    end
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
`endif
    wait (grb == 3'b100 || grb == 3'b010);
    #1_000_000;
    if (grb == 3'b100) $display("PASS  the tape's program: border green at %0d ms", $time / 1_000_000);
    else begin $display("FAIL  the tape's program: border red at %0d ms", $time / 1_000_000); fails = fails + 1; end
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
`endif
    #2_000_000;
    $display("F12 at %0d ms", $time / 1_000_000);
    send_byte(8'h07); #30_000_000; send_byte(8'hF0); send_byte(8'h07);   // F12 -> NMI -> menu
`ifdef PAGE_TEST
    wait_row(3, "  MANIC   .TAP                  ");
`else
    wait_row(6, "  EXACT   .Z80                  ");
`endif
    wait_bar(2);
    $display("menu complete at %0d ms:", $time / 1_000_000);
    show_screen;
`ifdef FRAME_TEST
    // the picture itself (tb_720p.sh): capture a frame, check it, save it
    frame("frame720.ppm");
    check_frame;
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
`endif
    expect_row(0,  " KRASNODAR-48  SD CARD LOADER   ");
    expect_row(2,  "  JETPAC  .Z80                  ");
    expect_row(3,  "  MANIC   .TAP                  ");
`ifndef PAGE_TEST
    expect_row(4,  "  HORACE  .SNA                  ");
    expect_row(5,  "  TINY    .TAP                  ");
    expect_row(6,  "  EXACT   .Z80                  ");
    expect_row(7,  "                                ");
`endif
    expect_row(22, " 7/6/arrows  ENTER  SPACE=exit  ");
    // colours: title and help bars, the selection bar on the first game,
    // plain text elsewhere (this caught z80asm reading A_BAR as register A)
    expect_attr(0, 8'h4F); expect_attr(2, 8'h68); expect_attr(3, 8'h38);
    expect_attr(7, 8'h38); expect_attr(22, 8'h4F);
    frame("menu.ppm");
`ifdef PAGE_TEST
    // MAXF = 2 (tb_sdpage.sh): pages of two games.  Each key waits for the
    // bar, so it is sent only once the menu is listening.
    key_at(2, 8'h36);                      // down: MANIC
    key_at(3, 8'h36);                      // down from the bottom row: page 2
    wait_bar(2);
    expect_row(2, "  HORACE  .SNA                  ");
    expect_row(3, "  TINY    .TAP                  ");
    expect_row(4, "                                ");
    key_at(2, 8'h36); key_at(3, 8'h36);    // and page 3: one game
    wait_bar(2);
    expect_row(2, "  EXACT   .Z80                  ");
    expect_row(3, "                                ");
    key_at(2, 8'h36);                      // last game: down does nothing
    key_at(2, 8'h3D);                      // up from the top row: page 2, bottom row
    wait_bar(3);
    expect_row(2, "  HORACE  .SNA                  ");
    expect_row(3, "  TINY    .TAP                  ");
    key_at(3, 8'h3D);                      // up: HORACE
    key_at(2, 8'h5A);                      // ENTER on it (.SNA: shown, menu stays)
    wait_row(23, " chosen: HORACE  .SNA           ");
    expect_row(23, " chosen: HORACE  .SNA           ");
    key_at(2, 8'h3D);                      // up: back to page 1, MANIC
    wait_bar(3);
    expect_row(2, "  JETPAC  .Z80                  ");
    expect_row(3, "  MANIC   .TAP                  ");
    $display("at %0d ms", $time / 1_000_000);
`else
    key_at(2, 8'h36); key_at(3, 8'h36);    // 6: down twice, to HORACE
    key_at(4, 8'h5A);                      // ENTER (.SNA: shown, menu stays)
    wait_row(23, " chosen: HORACE  .SNA           ");
    expect_row(23, " chosen: HORACE  .SNA           ");
    $display("at %0d ms", $time / 1_000_000);

    // --- load the test snapshot -------------------------------------------------
    for (i = 0; i < 49152; i = i + 1) wmem[i] = 8'hxx;
    key_at(4, 8'h3D); key_at(3, 8'h3D);    // 7: up twice, to JETPAC.Z80
    wait_bar(2); #5_000_000;
    loading = 1'b1;
    tap(8'h5A);                            // ENTER
    $display("loading at %0d ms", $time / 1_000_000);
    wait (grb == 3'b100 || grb == 3'b010);
    #1_000_000;
    if (grb == 3'b100) $display("PASS  snapshot's register check: border green at %0d ms", $time / 1_000_000);
    else begin $display("FAIL  snapshot's register check: border red at %0d ms", $time / 1_000_000); fails = fails + 1; end
    begin : memcheck
      integer a, bad;
      bad = 0;
      for (a = 16'h4000; a < 32'h10000; a = a + 1)
        // not checked: the checker's save area, and the bytes under the
        // game's SP (FF00) that the loader's calls used
        if (!(a >= 16'h8F00 && a < 16'h8F18) && !(a >= 16'hFEE0 && a < 16'hFF00) &&
            wmem[a - 16'h4000] !== zmem[a - 16'h4000]) begin
          if (bad < 8) $display("FAIL  %h: loaded %h, want %h", a[15:0], wmem[a - 16'h4000], zmem[a - 16'h4000]);
          bad = bad + 1;
        end
      if (bad == 0) $display("PASS  all 48K loaded as the image");
      else begin $display("FAIL  %0d bytes differ", bad); fails = fails + 1; end
    end
`endif
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
  end
`ifdef GAME_TAP
  initial begin #12_000_000_000 $display("TIMEOUT"); $finish; end   // a real tape: 30K+ at card speed
`else
  initial begin #6_000_000_000 $display("TIMEOUT"); $finish; end
`endif
endmodule
