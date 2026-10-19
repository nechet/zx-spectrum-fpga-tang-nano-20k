// -----------------------------------------------------------------------------
// The Krasnodar-48 board netlist on the Tang Nano 20K, on HDMI.
//
// The board is transcribed from the EasyEDA schematic.  Its raster is 896
// clocks a line and 312 lines a frame whatever it is clocked at.  Two
// video back ends, chosen at build time:
//
//   576p (default)  scan_doubler.v: 896 x 624 at 27 MHz, two lines per
//                   board line
//       27 MHz crystal -+- /2 -> 13.5 MHz, the board's master clock
//                       +- PLL x5 -> 135 MHz: the board's logic and the TMDS
//                          serialisers; /5 of it is the 27 MHz pixel clock
//   720p (HDMI_720P) ../tang20k/scan_tripler.v: 1792 x 936 at 81 MHz, three
//                   lines per board line; one PLL makes every clock (below)
//
// Either way one output line is an exact fraction of an input line, so the
// two rasters are locked and the picture cannot tear.
//
// The board wants 14 MHz, which would give the Spectrum's exact 15.625 kHz and
// 50.08 Hz and let the output be standard 576p50.  But 14 MHz needs a second
// PLL, and a second PLL is the one thing that has ever stopped this board's
// HDMI output working -- twice, with an otherwise byte-identical back end and
// identical placement.  13.5 MHz needs no PLL at all.  The cost is that the
// machine runs 3.6 % slow and the mode is 30.1 kHz / 48.3 Hz rather than
// 31.25 / 50.08; the monitor already accepts a non-standard 624-line frame.
//
// LEDs (active low):
//   LED0  the board is out of reset
//   LED1  TMDS PLL locked
//   LED2  the board's frame sync is running
//   LED3  unused
//   LED4  /SYNC divided down to a blink -- the video timing chain is alive
//   LED5  unused
//
// The HDMI output is held in reset only by its own PLL, never by anything on
// the board side, so a fault there cannot take the picture with it.
// -----------------------------------------------------------------------------
`default_nettype none

module top #(
    // The TMDS encoders and serialisers cost a lot of simulation time and
    // contribute nothing to the picture data, so the frame renderer leaves
    // them out.  Always 1 for anything that gets built.
    parameter WITH_HDMI = 1,
    // 1: true LVDS output buffers (TLVDS_OBUF, LVDS25 pairs), as the Tang
    //    Nano 20K's HDMI pins have -- the builds set this (../tang20k/*/top20k.v)
    // 0: emulated LVDS (ELVDS_OBUF), what the simulation stubs provide
    parameter TRUE_LVDS = 0,
    // The Tang Nano 20K's reset button on pin 88 idles LOW (Sipeed's own
    // constraints pull it down), so the builds set 0: an active-low reset
    // there would hold the design in reset for ever.  The testbenches use 1.
    parameter RST_ACTIVE_LOW = 1
) (
    input  wire       clk,          // 27 MHz, pin 4
    input  wire       rst_i,        // button S2, active low
    output wire [5:0] led,          // active low
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
`ifdef PS2_KBD
    input  wire       ps2_clk,      // PS/2 keyboard, 3.3 V, receive only
    input  wire       ps2_data,
`endif
`ifdef PS2_UART
    output wire       uart_tx,      // debug: PS/2 monitor to the USB serial port
`endif
`ifdef SD_LOADER
    output wire       sd_clk,       // microSD card, SPI mode (../tang20k/sd_bridge.v)
    output wire       sd_cmd,
    output wire       sd_dat3,
    input  wire       sd_dat0,
    input  wire       nmi_btn,      // loader menu button, active high
`endif
    output wire [2:0] tmds_d_n);

  // --- clocks ----------------------------------------------------------------
`ifdef CLK14
  // Tang Nano 20K: the board's intended 14 MHz, with a 28 MHz pixel clock --
  // 31.25 kHz / 50.08 Hz, 576p50's rates.  The 13.5/27 MHz scheme below gives
  // 30.13 kHz / 48.29 Hz, which the 20K's monitor refuses to sync to.  Two
  // PLLs, cascaded; see ../tang20k/pll_28.v and pll_140.v.
  wire clk_pixel, clk_x5, clk14, pll28_lock, pll140_lock;
  pll_28  pll_pix  (.clkin(clk), .clkout(clk_pixel), .lock(pll28_lock));
  pll_140 pll_tmds (.clkin(clk_pixel), .clkout(clk_x5), .clkout_div10(clk14),
                    .lock(pll140_lock));
  // named for the 135 MHz PLL of the default build: drives LED1 and the serialiser reset
  wire pll135_lock = pll28_lock & pll140_lock;
`elsif HDMI_720P
  // Tang Nano 20K, 1280x720 (../tang20k/scan_tripler.v): one PLL
  // makes every clock.  405 MHz drives the serialisers; CLKDIV /5 of it is
  // the 81 MHz pixel clock, in phase as below; CLKOUTD3, 405 / 3, is the
  // board's 135 MHz, and the board's 13.5 MHz is that divided by 10 (f14
  // below).  81 is exactly 6 x 13.5, so three output lines are exactly one
  // board line.
  wire clk_ser, clk_x5, pll135_lock;
  pll_405 pll_all (.clkin(clk), .clkout(clk_ser), .clkout_d3(clk_x5), .lock(pll135_lock));
  wire clk_pixel;
  CLKDIV pix_div (.CLKOUT(clk_pixel), .HCLKIN(clk_ser), .RESETN(pll135_lock), .CALIB(1'b0));
  defparam pix_div.DIV_MODE = "5";
  defparam pix_div.GSREN    = "false";
`else
  wire clk_x5, pll135_lock;
  pll_135 pll_tmds (.clkin(clk), .clkout(clk_x5), .lock(pll135_lock));
`ifdef GW2A
  // The HDMI serialisers (OSER10) need PCLK to be exactly FCLK / 5 *in phase*.
  // The crystal pin and the PLL output have the right ratio but a phase that
  // depends on routing, so on the 20K the picture synced in some builds and
  // not in others.  CLKDIV derives the pixel clock from clk_x5 itself, which
  // is how Gowin's own HDMI reference designs do it.
  wire clk_pixel;
  CLKDIV pix_div (.CLKOUT(clk_pixel), .HCLKIN(clk_x5), .RESETN(pll135_lock), .CALIB(1'b0));
  defparam pix_div.DIV_MODE = "5";
  defparam pix_div.GSREN    = "false";
`else
  wire clk_pixel = clk;                    // 27 MHz, straight from the crystal
`endif

  // The board clock is the crystal halved -- no PLL, and exactly half the
  // pixel clock, which is what locks the two rasters together.
  reg clk_half = 1'b0;
  always @(posedge clk) clk_half <= ~clk_half;
  wire clk14 = clk_half;                   // 13.500 MHz
`endif

`ifndef HDMI_720P
  wire clk_ser = clk_x5;                   // the serialisers' 5x clock
`endif

  // --- board reset -----------------------------------------------------------
  // Held until the board's own clock is stable, then long enough for the DRAM.
  reg [19:0] rstcnt = 20'd0;               // ~39 ms at 27 MHz
  wire por_done = &rstcnt;
  always @(posedge clk) if (!por_done) rstcnt <= rstcnt + 20'd1;
  wire rst_released = RST_ACTIVE_LOW ? rst_i : ~rst_i;
  wire res_n = por_done & rst_released;
`ifdef HDMI_720P
  // The board runs on the PLL's divided output, whose edges keep no fixed
  // phase to the crystal's: bring the reset across with two flip-flops.
  reg [1:0] res_s = 2'b00;
  always @(posedge clk_x5) res_s <= {res_s[0], res_n};
  wire res_n_sys = res_s[1];
`else
  wire res_n_sys = res_n;
`endif

  // --- the board -------------------------------------------------------------
  // vid_sync_n is the board's composite sync; vid_hsync_n and vid_vsync_n are
  // the separate line and frame syncs, exported because composite here is
  // SSI xor ~-KSI -- during the frame pulse the line sync inverts rather than
  // widening, so a scan doubler cannot recover them by pulse width.
  wire vid_red, vid_green, vid_blue, vid_bright;
  wire vid_sync_n, vid_hsync_n, vid_vsync_n;
  wire tape_out, sound;
  wire [7:0] pa, pb, pc;
`ifdef BOOT_LEDS
  wire [15:0] dbg_a;                // CPU address bus, from a debug netlist
  wire        dbg_m1_n;             // Z80 /M1 (opcode fetch)
`endif

  // The board's 14 MHz, as data in the clk_sys domain.  Every register on the
  // board now runs on clk_sys and detects edges of this, so it must not be a
  // clock net of its own.  clk_half is a register on the 27 MHz crystal clock,
  // which clk_x5 is an exact multiple of, so one resampling stage is a
  // timing-analysed path.  On the CLK14 build clk14 is a PLL output in phase
  // with clk_x5 -- sampling it would race -- so divide clk_x5 by 10 instead.
  // The same on the 720p build, where clk_x5 is the PLL's 405 / 3 and keeps
  // no fixed phase to the crystal.
`ifdef CLK14
  `define F14_FROM_SYS
`endif
`ifdef HDMI_720P
  `define F14_FROM_SYS
`endif
`ifdef F14_FROM_SYS
  reg [3:0] f14_div = 4'd0;
  reg       f14 = 1'b0;
  always @(posedge clk_x5) begin
    f14_div <= (f14_div == 4'd9) ? 4'd0 : f14_div + 4'd1;
    f14     <= (f14_div < 4'd5);
  end
`else
  reg f14 = 1'b0;
  always @(posedge clk_x5) f14 <= clk14;
`endif

`ifdef PS2_KBD
  // --- PS/2 keyboard -----------------------------------------------------------
  // The CPU selects keyboard rows with A8..A15 (exported from the board
  // netlist) and reads the five columns back on KD1..KD5; ps2_keyboard.v (in
  // ../tang20k) keeps the key state from the PS/2 scancodes.
  wire [7:0] a_hi;
  wire [4:0] kd;
  wire kb_clk_low, kb_data_low, kb_clk_fall, kb_valid, kb_err, kb_any;
  wire [7:0]  kb_code;
  wire [39:0] kb_down;
  wire kb_f12;
  ps2_keyboard kbd (.clk(clk_x5), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
                    .a_hi(a_hi), .kd(kd), .key_f12(kb_f12),
                    .dbg_clk_low(kb_clk_low), .dbg_data_low(kb_data_low),
                    .dbg_clk_fall(kb_clk_fall), .dbg_valid(kb_valid),
                    .dbg_err(kb_err), .dbg_any_down(kb_any),
                    .dbg_code(kb_code), .dbg_down(kb_down));
`ifdef PS2_UART
  ps2_uart_mon #(.CLK_HZ(135_000_000)) mon (.clk(clk_x5), .code(kb_code),
                    .valid(kb_valid), .err(kb_err), .down(kb_down), .kd(kd), .clk_fall(kb_clk_fall),
                    .tx(uart_tx));
`endif
`endif

  // --- the 8255's port pins: an edge connector ---------------------------------
  // Off-board drivers, wired-AND with the 8255 (bus_resolve.py --connector);
  // 1 = released.  The SD loader is the only device plugged in.
  wire [7:0] pa_ext, pb_ext, pc_ext;
  wire       nmi_n;
  wire       rom_bank;                // the ROM's second bank (ROM_BANKS)
`ifdef SD_LOADER
  // ../tang20k: sd_bridge.v (card, FAT32, the 8255 protocol) runs
  // on the 27 MHz board clock; nmi_gen.v turns F12 / the button into /NMI,
  // which the patched ROM (mk_sdrom.py) answers with the games menu.
  wire       sd_ack, sd_mounted, sd_error;
  wire [7:0] sd_answer;
  sd_bridge #(.CLK_HZ(27_000_000)) sdb (
      .clk(clk), .clk_sys(clk_x5), .pb(pb), .strobe(pc[4]),
      .pa_ext(sd_answer), .ack_ext(sd_ack),
      .sd_sck(sd_clk), .sd_cs_n(sd_dat3), .sd_mosi(sd_cmd), .sd_miso(sd_dat0),
      .mounted(sd_mounted), .error(sd_error));
  wire nmi_gen_n;
`ifdef PS2_KBD
  wire nmi_f12 = kb_f12;
`else
  wire nmi_f12 = 1'b0;
`endif
  nmi_gen #(.CLK_HZ(135_000_000)) nmig (.clk(clk_x5), .f12(nmi_f12), .btn(nmi_btn), .nmi_n(nmi_gen_n));
`ifdef SD_NONMI
  assign nmi_n = 1'b1;                        // diagnostic: NMI disconnected
`else
  assign nmi_n = nmi_gen_n;
`endif
  // LED probes for the SD build: any NMI since power-up (sticky), button
  // level, F12, card mounted, SD error.
  reg nmi_seen = 1'b0;
  always @(posedge clk_x5) if (!nmi_gen_n) nmi_seen <= 1'b1;
  reg [1:0] btn_s = 2'b00;
  always @(posedge clk_x5) btn_s <= {btn_s[0], nmi_btn};
  assign pa_ext = sd_answer;
  assign pb_ext = 8'hFF;
  assign pc_ext = {7'h7F, sd_ack};            // PC0: ACK
  // PC5 low selects the shadow ROM bank, as a divIDE pages in its EPROM.
  // After reset the 8255's ports are inputs, the board's pull-ups hold PC5
  // high, and the machine starts in the stock ROM; the menu's mode word 91h
  // makes port C an output (all zero) and bank 1 appears, mode 9Bh -- the
  // reset state -- brings the stock ROM back.  Programs never write the
  // 8255, so they always see the stock ROM.
  assign rom_bank = ~pc[5];
`else
  assign rom_bank = 1'b0;
  assign pa_ext = 8'hFF;
  assign pb_ext = 8'hFF;
  assign pc_ext = 8'hFF;
  assign nmi_n  = 1'b1;
`endif

  krasnodar48_synth kras (
      .clk14   (f14),
      // The board's RC delay lines generate its DRAM timing -- /CAS behind
      // /RAS, and the row/column multiplexer switching in between.  Resolving
      // 7.9 ns and 20.2 ns needs a clock far faster than the board's own, so
      // the TMDS PLL's 135 MHz does double duty here.
      .clk_sys (clk_x5),
`ifdef HOLD_CPU
      .res_n   (1'b0),                  // diagnostic: CPU held in reset, video runs
`else
      .res_n   (res_n_sys),
`endif
      .nmi_n   (nmi_n),
      .rom_bank(rom_bank),
      .wait_n  (1'b1),
      .busrq_n (1'b1),
      .jp_ru6  (1'b1),              // RAM type jumper
      .tape_in (1'b0),
`ifdef PS2_KBD
      .KD1 (kd[0]), .KD2 (kd[1]), .KD3 (kd[2]), .KD4 (kd[3]), .KD5 (kd[4]),
      .A8_out (a_hi[0]), .A9_out (a_hi[1]), .A10_out (a_hi[2]), .A11_out (a_hi[3]),
      .A12_out (a_hi[4]), .A13_out (a_hi[5]), .A14_out (a_hi[6]), .A15_out (a_hi[7]),
`else
      .KD1 (1'b1), .KD2 (1'b1), .KD3 (1'b1), .KD4 (1'b1), .KD5 (1'b1),   // no keyboard
`endif
      .vid_red (vid_red), .vid_green (vid_green), .vid_blue (vid_blue),
      .vid_bright (vid_bright), .vid_sync_n (vid_sync_n),
      .vid_hsync_n (vid_hsync_n), .vid_vsync_n (vid_vsync_n),
      .tape_out (tape_out), .sound (sound),
      .PA0(pa[0]), .PA1(pa[1]), .PA2(pa[2]), .PA3(pa[3]),
      .PA4(pa[4]), .PA5(pa[5]), .PA6(pa[6]), .PA7(pa[7]),
      .PB0(pb[0]), .PB1(pb[1]), .PB2(pb[2]), .PB3(pb[3]),
      .PB4(pb[4]), .PB5(pb[5]), .PB6(pb[6]), .PB7(pb[7]),
      .PC0(pc[0]), .PC1(pc[1]), .PC2(pc[2]), .PC3(pc[3]),
      .PC4(pc[4]), .PC5(pc[5]), .PC6(pc[6]), .PC7(pc[7]),
      .PA0_ext(pa_ext[0]), .PA1_ext(pa_ext[1]), .PA2_ext(pa_ext[2]), .PA3_ext(pa_ext[3]),
      .PA4_ext(pa_ext[4]), .PA5_ext(pa_ext[5]), .PA6_ext(pa_ext[6]), .PA7_ext(pa_ext[7]),
      .PB0_ext(pb_ext[0]), .PB1_ext(pb_ext[1]), .PB2_ext(pb_ext[2]), .PB3_ext(pb_ext[3]),
      .PB4_ext(pb_ext[4]), .PB5_ext(pb_ext[5]), .PB6_ext(pb_ext[6]), .PB7_ext(pb_ext[7]),
      .PC0_ext(pc_ext[0]), .PC1_ext(pc_ext[1]), .PC2_ext(pc_ext[2]), .PC3_ext(pc_ext[3]),
      .PC4_ext(pc_ext[4]), .PC5_ext(pc_ext[5]), .PC6_ext(pc_ext[6]), .PC7_ext(pc_ext[7])
`ifdef BOOT_LEDS
      , .dbg_a(dbg_a), .dbg_m1_n(dbg_m1_n)
`endif
      );

  // --- line doubler ----------------------------------------------------------
  // The window comes from measurement, not from the datasheet: the picture
  // starts 159 board clocks into the line and 20 lines into the frame, and is
  // 704 clocks by 288 lines -- 352 x 288 Spectrum pixels, which is 256 x 192
  // of display inside a 48-pixel border.  288 doubled is 576 exactly.
  wire [10:0] ox;
  wire [9:0]  oy;
  wire dbl_hsync, dbl_vsync, dbl_active;
  wire [3:0] rgbi;

  // The board now changes only on clk_x5 ticks, a few ticks after each edge of
  // its 14 MHz (f14).  Sampling its video on clk14 -- a different clock --
  // caught signals mid-change (Gowin: failing paths from the video counters
  // into the line buffer; on the 20K, no sync).  So register the video
  // outputs on clk_x5 and write the line buffer on clk_x5, once per board
  // pixel, at f14's rising edge: the sample is then the value from the end of
  // the previous pixel, stable for most of a 14 MHz period.
  reg f14_dd = 1'b0;
  reg [3:0] rgbi_q = 4'd0;
  reg hs_q = 1'b0, vs_q = 1'b0;
  always @(posedge clk_x5) begin
    f14_dd <= f14;
    rgbi_q <= {vid_bright, vid_red, vid_green, vid_blue};
    hs_q   <= ~vid_hsync_n;              // the doubler wants active high
    vs_q   <= ~vid_vsync_n;
  end
  wire ce_pix = f14 & ~f14_dd;

`ifdef HDMI_720P
  // 1280 x 720: each Spectrum pixel 3 x 3, the 16:9 sides filled with the
  // border (../tang20k/scan_tripler.v).  Same window.
  localparam O_HTOTAL = 1792, O_VTOTAL = 936;
  wire slip_small, slip_big;
  scan_tripler #(
      .H_IN_TOTAL  (896),
      .H_VIS_START (159),
      .V_VIS_START (20)
  ) dbl (
      .clk_in    (clk_x5),
      .ce_in     (ce_pix),
      .rgbi_in   (rgbi_q),
      .hsync_in  (hs_q),
      .vsync_in  (vs_q),
      .clk_pixel (clk_pixel),
      .ox (ox), .oy (oy),
      .hsync_out (dbl_hsync),
      .vsync_out (dbl_vsync),
      .active_out(dbl_active),
      .rgbi_out  (rgbi),
      .slip_small(slip_small),
      .slip_big  (slip_big));
`else
  localparam O_HTOTAL = 896, O_VTOTAL = 624;
  assign ox[10] = 1'b0;
  scan_doubler #(
      .H_IN_TOTAL  (896),
      .H_VIS_START (159),
      .H_VIS_LEN   (704),
      .V_VIS_START (20)
  ) dbl (
      .clk_in    (clk_x5),
      .ce_in     (ce_pix),
      .rgbi_in   (rgbi_q),
      .hsync_in  (hs_q),
      .vsync_in  (vs_q),
      .clk_pixel (clk_pixel),
      .ox (ox[9:0]), .oy (oy),
      .hsync_out (dbl_hsync),
      .vsync_out (dbl_vsync),
      .active_out(dbl_active),
      .rgbi_out  (rgbi));
`endif

  // --- colour ----------------------------------------------------------------
  // A Spectrum's two brightness levels: the normal one is about 80 % of full.
  wire [7:0] lvl = rgbi[3] ? 8'hFF : 8'hCD;
  wire [7:0] r8  = rgbi[2] ? lvl : 8'h00;
  wire [7:0] g8  = rgbi[1] ? lvl : 8'h00;
  wire [7:0] b8  = rgbi[0] ? lvl : 8'h00;

  // --- HDMI ------------------------------------------------------------------
  // Hold the serialisers in reset until the TMDS PLL is locked and a few
  // thousand pixel clocks have passed, so all three start on the same 10-bit
  // boundary.  This deliberately does not depend on the board's PLL.
  reg [11:0] tmdsrst = 12'd0;
  always @(posedge clk_pixel)
    if (!pll135_lock)      tmdsrst <= 12'd0;
    else if (!(&tmdsrst))  tmdsrst <= tmdsrst + 12'd1;
  wire tmds_reset = ~(&tmdsrst);

  generate
    if (WITH_HDMI) begin : hdmi_gen
`ifdef HDMI_SELFTEST
      // Diagnostic: feed the encoder from a known-good 576p50 test-pattern
      // generator instead of the scan doubler, with the whole board still
      // running.  If this syncs and the normal build does not, the doubler's
      // output (i.e. the board's own sync) is what the monitor rejects.
      wire [9:0] st_x, st_y;
      wire st_hs, st_vs, st_act;
      wire [7:0] st_r, st_g, st_b;
      video_timing selftest (.clk_pixel(clk_pixel), .cx(st_x), .cy(st_y),
          .hsync(st_hs), .vsync(st_vs), .active(st_act),
          .red(st_r), .green(st_g), .blue(st_b));
`ifdef SELFTEST_MIX
      // Diagnostic: the generator's timing, but colours XORed with the
      // doubler's pixels, so the board, CPU and doubler stay in the design.
      wire [7:0] h_r = st_r ^ r8, h_g = st_g ^ g8, h_b = st_b ^ b8;
`else
      wire [7:0] h_r = st_r, h_g = st_g, h_b = st_b;
`endif
      wire h_hs = st_hs, h_vs = st_vs, h_act = st_act;
      wire [10:0] h_x = {1'b0, st_x};
      wire [9:0]  h_y = st_y;
`else
      wire [7:0] h_r = r8, h_g = g8, h_b = b8;
      wire h_hs = dbl_hsync, h_vs = dbl_vsync, h_act = dbl_active;
      wire [10:0] h_x = ox;
      wire [9:0]  h_y = oy;
`endif
      // 576p's syncs are negative-going, 720p's positive
`ifdef HDMI_720P
      wire h_hs_tx = h_hs, h_vs_tx = h_vs;
`else
      wire h_hs_tx = ~h_hs, h_vs_tx = ~h_vs;
`endif
`ifdef HDMI_AUDIO
      // Sound over HDMI (tang20k: hdmi_audio_out.sv, beeper_audio.v):
      // the beeper and tape outputs as 48 kHz samples, sent in data islands
      // in the horizontal blanking.  The raster position comes from the
      // doubler, so the islands sit at fixed places in its 896 x 624 frame.
      wire        clk_audio;
      wire [15:0] audio;
`ifdef HDMI_720P
`ifdef AUDIO_TONE_TEST
      // diagnostic: a 1 kHz tone, half a second on and off, in place of the tape bit
      reg [26:0] tt = 27'd0;
      reg [15:0] tdv = 16'd0;
      reg        tone = 1'b0;
      always @(posedge clk_pixel) begin
        tt <= tt + 27'd1;
        if (tdv == 16'd40499) begin tdv <= 16'd0; tone <= ~tone & ~tt[25]; end
        else tdv <= tdv + 16'd1;
      end
      wire tape_mix = tone;
`else
      wire tape_mix = tape_out;
`endif
      beeper_audio #(.CLK_DIV(3)) beep (.clk_pixel(clk_pixel), .speaker(sound), .tape(tape_mix),
                         .clk_audio(clk_audio), .sample(audio));
      hdmi_audio_out #(.TRUE_LVDS(TRUE_LVDS),
          .H_ACTIVE(1280), .H_TOTAL(1792), .V_ACTIVE(720), .V_TOTAL(936),
          // VIC 0: not a CEA-861 format.  1792 x 936 at 48.3 Hz is too far
          // from 720p50 (1980 x 750) to claim it, and a monitor that compares
          // the claim with what it measures may mute the sound.
          .VIDEO_ID_CODE(0),
          .VIDEO_RATE(81.0E6)) hdmi (
`else
      beeper_audio beep (.clk_pixel(clk_pixel), .speaker(sound), .tape(tape_out),
                         .clk_audio(clk_audio), .sample(audio));
      hdmi_audio_out #(.TRUE_LVDS(TRUE_LVDS)) hdmi (
`endif
          .clk_pixel (clk_pixel),
          .clk_x5    (clk_ser),
          .reset     (tmds_reset),
          .cx (h_x), .cy (h_y),
          .red (h_r), .green (h_g), .blue (h_b),
          .hsync_tx  (h_hs_tx),
          .vsync_tx  (h_vs_tx),
          .clk_audio (clk_audio), .audio_l (audio), .audio_r (audio),
          .tmds_clk_p (tmds_clk_p), .tmds_clk_n (tmds_clk_n),
          .tmds_d_p (tmds_d_p),     .tmds_d_n (tmds_d_n));
`else
      hdmi_out #(.TRUE_LVDS(TRUE_LVDS)) hdmi (
          .clk_pixel (clk_pixel),
          .clk_x5    (clk_ser),
          .reset     (tmds_reset),
          .red (h_r), .green (h_g), .blue (h_b),
          .hsync_tx  (h_hs_tx),
          .vsync_tx  (h_vs_tx),
          .active    (h_act),
          .tmds_clk_p (tmds_clk_p), .tmds_clk_n (tmds_clk_n),
          .tmds_d_p (tmds_d_p),     .tmds_d_n (tmds_d_n));
`endif
    end else begin : no_hdmi
      assign {tmds_clk_p, tmds_clk_n} = 2'b00;
      assign {tmds_d_p, tmds_d_n} = 6'b0;
    end
  endgenerate

  // --- LEDs ------------------------------------------------------------------
  // /SYNC runs at 15.6 kHz, far too fast to see, so divide it to a blink.
  reg [11:0] syncdiv = 12'd0;
  reg sync_d = 1'b0, vs_d = 1'b0, frame_seen = 1'b0;
  always @(posedge clk) begin
    sync_d <= vid_sync_n;
    if (sync_d && !vid_sync_n) syncdiv <= syncdiv + 12'd1;
    vs_d <= vid_vsync_n;
    if (vs_d && !vid_vsync_n) frame_seen <= ~frame_seen;
  end

  // --- raster checkers on the spare LEDs (sticky) ---------------------------
  // Kept from the 20K bring-up, when the doubler's output did not sync while a
  // known-good generator through the same encoder did -- they check, on the
  // hardware, whether the raster the doubler emits (and the board raster it
  // follows) is actually regular.  Each flag latches on the first violation
  // after a settling period; a frame is only judged once a full frame has been
  // seen since settling, so a partly-counted first frame cannot trip it.
  //   LED3  an output line != O_HTOTAL pixel clocks, or a frame != O_VTOTAL lines
  //   LED5  a board line   != 896 board clocks, or a board frame   != 312 lines
`ifdef SYNTHESIS
  localparam OW = 25, IW = 24;                 // ~1.2 s
`else
  localparam OW = 21, IW = 20;                 // ~78 ms: past the ~39 ms board reset
`endif
  reg [OW-1:0] owarm = {OW{1'b0}};
  reg [10:0] olen = 11'd0, olines = 11'd0;
  reg ohs_d = 1'b0, ovs_d = 1'b0, oframe_ok = 1'b0;
  reg o_lenerr = 1'b0, o_frmerr = 1'b0;
  reg [10:0] o_badlen = 11'd0, o_badlines = 11'd0;   // first offending values
  always @(posedge clk_pixel) begin
    if (!(&owarm)) owarm <= owarm + 1'b1;
    ohs_d <= dbl_hsync;
    ovs_d <= dbl_vsync;
    if (dbl_hsync && !ohs_d) begin
      if ((&owarm) && olen != O_HTOTAL - 1 && !o_lenerr) begin
        o_lenerr <= 1'b1;  o_badlen <= olen + 11'd1;
      end
      olen   <= 11'd0;
      olines <= olines + 11'd1;
    end else
      olen <= olen + 11'd1;
    if (dbl_vsync && !ovs_d) begin
      // a line edge on this same clock belongs to the frame now ending
      if (oframe_ok && (olines + (dbl_hsync && !ohs_d)) != O_VTOTAL && !o_frmerr) begin
        o_frmerr <= 1'b1;  o_badlines <= olines + (dbl_hsync && !ohs_d);
      end
      if (&owarm) oframe_ok <= 1'b1;
      olines <= 11'd0;
    end
  end
  wire oerr = o_lenerr | o_frmerr;

  reg [IW-1:0] iwarm = {IW{1'b0}};
  reg [10:0] ilen = 11'd0, ilines = 11'd0;
  reg ihs_d = 1'b1, ivs_d = 1'b1, iframe_ok = 1'b0;
  reg i_lenerr = 1'b0, i_frmerr = 1'b0;
  reg [10:0] i_badlen = 11'd0, i_badlines = 11'd0;
  // On clk_x5, once per board clock (ce_pix), for the same reason as the
  // doubler's write side: the board's outputs change on clk_x5 ticks.
  always @(posedge clk_x5) if (ce_pix) begin
    if (!(&iwarm)) iwarm <= iwarm + 1'b1;
    ihs_d <= vid_hsync_n;
    ivs_d <= vid_vsync_n;
    if (ihs_d && !vid_hsync_n) begin
      if ((&iwarm) && ilen != 11'd895 && !i_lenerr) begin
        i_lenerr <= 1'b1;  i_badlen <= ilen + 11'd1;
      end
      ilen   <= 11'd0;
      ilines <= ilines + 11'd1;
    end else
      ilen <= ilen + 11'd1;
    if (ivs_d && !vid_vsync_n) begin
      if (iframe_ok && (ilines + (ihs_d && !vid_hsync_n)) != 11'd312 && !i_frmerr) begin
        i_frmerr <= 1'b1;  i_badlines <= ilines + (ihs_d && !vid_hsync_n);
      end
      if (&iwarm) iframe_ok <= 1'b1;
      ilines <= 11'd0;
    end
  end
  wire ierr = i_lenerr | i_frmerr;

`ifdef PS2_LEDS
  // --- PS/2 probe (debug build only) ------------------------------------------
  // Test points along the keyboard path, lit = true.  Pulses are far too short
  // to see (one CLK edge lasts ~40 us), so they retrigger a 0.25 s stretcher --
  // a 74123 monostable, in effect.
  //   LED0 CLK edges seen (stretched)     LED3 a Spectrum key is held
  //   LED1 good byte received (stretched) LED4 a KD line pulled low (stretched):
  //   LED2 rejected frame (latched)            the CPU's row select reached it
  //   LED5 heartbeat, ~1 Hz: this build is running
  reg [24:0] st_edge = 25'd0, st_byte = 25'd0, st_kd = 25'd0;
  reg [26:0] beat = 27'd0;
  reg        bad = 1'b0;
  always @(posedge clk_x5) begin
    if (kb_clk_fall) st_edge <= 25'd33_750_000; else if (st_edge != 0) st_edge <= st_edge - 25'd1;
    if (kb_valid)    st_byte <= 25'd33_750_000; else if (st_byte != 0) st_byte <= st_byte - 25'd1;
    if (kd != 5'h1F) st_kd   <= 25'd33_750_000; else if (st_kd   != 0) st_kd   <= st_kd   - 25'd1;
    if (!res_n) bad <= 1'b0; else if (kb_err) bad <= 1'b1;
    beat <= beat + 27'd1;
  end
  assign led = ~{beat[26], st_kd != 0, kb_any, bad, st_byte != 0, st_edge != 0};
`elsif SD_LOADER
  reg [26:0] sd_beat = 27'd0;
  always @(posedge clk_x5) sd_beat <= sd_beat + 27'd1;
`ifdef HDMI_720P
  // LED1, LED2: the tripler's realignment found the raster a pixel or two off
  // (synchroniser jitter, tolerated), or further off after the first lock
  assign led = ~{sd_beat[26], sd_error, sd_mounted, slip_big, slip_small, nmi_seen};
`else
  assign led = ~{sd_beat[26], sd_error, sd_mounted, nmi_f12, btn_s[1], nmi_seen};
`endif
`elsif BOOT_LEDS
  // --- boot milestones (debug build only) ------------------------------------
  // The hardware twin of tb_rom.v: an LED lights, and stays lit, the first time
  // the Z80 fetches an opcode from a given ROM routine.  /M1 is a board signal,
  // so it is synchronised to clk_x5 and its falling edge detected as data; the
  // address has been stable for half a T-state by then.
  //   LED0 RAM-DONE 11EF   memory check finished
  //   LED1 CLS      0D6B   screen clear started
  //   LED2 blinks ~1 Hz while IM1 interrupts (0038) keep arriving
  //   LED3 PO-MSG   0C0A   copyright being printed
  //   LED4 WAIT-KEY 15D4   start-up complete, waiting for a key
  //   LED5 restart: 0000 fetched again, or RST 8 (error) at 0008
  reg [2:0]  m1_s = 3'b111;
  reg        boot0 = 1'b0;
  reg [4:0]  ms = 5'd0;
  reg        restart = 1'b0;
  reg [4:0]  nint = 5'd0;
  reg        intblink = 1'b0;
  always @(posedge clk_x5) begin
    m1_s <= {m1_s[1:0], dbg_m1_n};
    if (!res_n) begin
      ms <= 5'd0; boot0 <= 1'b0; restart <= 1'b0;
    end else if (m1_s[2] && !m1_s[1]) begin
      case (dbg_a)
        16'h0000: begin if (boot0) restart <= 1'b1; boot0 <= 1'b1; end
        16'h0008: restart <= 1'b1;
        16'h11EF: ms[0] <= 1'b1;
        16'h0D6B: ms[1] <= 1'b1;
        16'h0038: begin
                    if (nint == 5'd24) begin nint <= 5'd0; intblink <= ~intblink; end
                    else nint <= nint + 5'd1;
                  end
        16'h0C0A: ms[3] <= 1'b1;
        16'h15D4: ms[4] <= 1'b1;
        default: ;
      endcase
    end
  end
  assign led = ~{restart, ms[4], ms[3], intblink, ms[1], ms[0]};
`else
  assign led = ~{ierr, syncdiv[11], oerr, frame_seen, pll135_lock, res_n};
`endif
endmodule
`default_nettype wire
