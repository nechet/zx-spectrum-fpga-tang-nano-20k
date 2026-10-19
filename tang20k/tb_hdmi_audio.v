// -----------------------------------------------------------------------------
// hdmi_audio_out + beeper_audio, read back the way a monitor reads them.
//
// A 896 x 624 raster (the scan doubler's) drives the output; the beeper bit
// toggles at 1 kHz.  Every 10-bit word the encoders produce is decoded:
// control codes, guard bands, TERC4.  Each data island is cut out between
// its guard bands and its packets reassembled from the lanes (Figure 5-4):
// lane 0 bit 2 carries the header, lanes 1 and 2 the four subpackets.  Then:
//   * every header and subpacket ECC is recomputed here, from the spec's
//     generator 1 + x^6 + x^7 + x^8, independently of packet_assembler
//   * every InfoFrame checksum adds up to zero
//   * the clock regeneration packet carries N = 6144 and CTS = 27000
//   * the audio samples arrive in the order beeper_audio made them, none
//     lost, none repeated, about 48000 / 48.29 Hz = 994 a frame
//   * each island is preceded by its preamble (CTL = 0101) and each active
//     line by the video preamble (0001) and guard band
//   * the picture is unchanged: every active pixel decodes to what was sent
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module tb_hdmi_audio;
`ifdef HDMI_720P
  // the 720p build: scan_tripler's 1792 x 936 raster at 81 MHz (tb_hdmi_audio.sh 720)
  localparam H_ACTIVE = 1280, H_TOTAL = 1792, V_ACTIVE = 720, V_TOTAL = 936;
  localparam HS0 = 1390, HS1 = 1430, VS0 = 725, VS1 = 730, CTS_WANT = 81000;
  reg clk = 1'b0;                        // 81 MHz pixel clock
  always #6.17284 clk = ~clk;
`else
  localparam H_ACTIVE = 720, H_TOTAL = 896, V_ACTIVE = 576, V_TOTAL = 624;
  localparam HS0 = 736, HS1 = 800, VS0 = 579, VS1 = 584, CTS_WANT = 27000;
  reg clk = 1'b0;                        // 27 MHz pixel clock
  always #18.518 clk = ~clk;
`endif
  localparam FRAMES = 3;

  reg clk5 = 1'b0;                       // not used by the checks
  always #3.7037 clk5 = ~clk5;

  // the raster, as scan_doubler makes it
  reg [10:0] cx = 11'd0;
  reg [9:0]  cy = 10'd0;
  always @(posedge clk) begin
    cx <= (cx == H_TOTAL - 1) ? 11'd0 : cx + 11'd1;
    if (cx == H_TOTAL - 1) cy <= (cy == V_TOTAL - 1) ? 10'd0 : cy + 10'd1;
  end
  wire active = cx < H_ACTIVE && cy < V_ACTIVE;
  wire hs = cx >= HS0 && cx < HS1, vs = cy >= VS0 && cy < VS1;
  wire [7:0] r = active ? cx[7:0] : 8'd0, g = active ? cy[7:0] : 8'd0, b = active ? (cx[7:0] ^ cy[7:0]) : 8'd0;

  // the beeper: a 1 kHz square wave, as BEEP would make
  reg spk = 1'b0;
  always #500_000 spk = ~spk;
  wire clk_audio;
  wire [15:0] sample;
`ifdef HDMI_720P
  beeper_audio #(.CLK_DIV(3)) beep (.clk_pixel(clk), .speaker(spk), .tape(1'b0),
                     .clk_audio(clk_audio), .sample(sample));
`else
  beeper_audio beep (.clk_pixel(clk), .speaker(spk), .tape(1'b0),
                     .clk_audio(clk_audio), .sample(sample));
`endif

  reg [3:0] rstc = 4'd0;
  always @(posedge clk) if (!(&rstc)) rstc <= rstc + 4'd1;
  wire reset = ~(&rstc);

  wire tcp, tcn; wire [2:0] tdp, tdn;
`ifdef HDMI_720P
  hdmi_audio_out #(.TRUE_LVDS(0), .H_ACTIVE(1280), .H_TOTAL(1792), .V_ACTIVE(720),
                   .V_TOTAL(936), .VIDEO_ID_CODE(19), .VIDEO_RATE(81.0E6)) dut (
      .clk_pixel(clk), .clk_x5(clk5), .reset(reset), .cx(cx), .cy(cy),
      .red(r), .green(g), .blue(b), .hsync_tx(hs), .vsync_tx(vs),
`else
  hdmi_audio_out #(.TRUE_LVDS(0)) dut (
      .clk_pixel(clk), .clk_x5(clk5), .reset(reset), .cx(cx), .cy(cy),
      .red(r), .green(g), .blue(b), .hsync_tx(~hs), .vsync_tx(~vs),
`endif
      .clk_audio(clk_audio), .audio_l(sample), .audio_r(sample),
      .tmds_clk_p(tcp), .tmds_clk_n(tcn), .tmds_d_p(tdp), .tmds_d_n(tdn));

  // --- the samples beeper_audio made, in order -------------------------------
  reg [15:0] made [0:8191];
  integer nmade = 0;
  always @(posedge clk_audio) begin made[nmade] = sample; nmade = nmade + 1; end

  // --- decoding ------------------------------------------------------------------
  integer fails = 0;
  integer lx, ly, k;
  task fail(input [8*64-1:0] what);
    begin if (fails < 20) $display("FAIL  %0s at line %0d px %0d", what, ly, lx); fails = fails + 1; end
  endtask

  function [4:0] terc4(input [9:0] w);   // 1x = not TERC4
    begin
      case (w)
        10'b1010011100: terc4 = 0;  10'b1001100011: terc4 = 1;
        10'b1011100100: terc4 = 2;  10'b1011100010: terc4 = 3;
        10'b0101110001: terc4 = 4;  10'b0100011110: terc4 = 5;
        10'b0110001110: terc4 = 6;  10'b0100111100: terc4 = 7;
        10'b1011001100: terc4 = 8;  10'b0100111001: terc4 = 9;
        10'b0110011100: terc4 = 10; 10'b1011000110: terc4 = 11;
        10'b1010001110: terc4 = 12; 10'b1001110001: terc4 = 13;
        10'b0101100011: terc4 = 14; 10'b1011000011: terc4 = 15;
        default: terc4 = 5'h10;
      endcase
    end
  endfunction
  function [2:0] ctl(input [9:0] w);     // control code -> {valid, c1, c0}
    begin
      case (w)
        10'b1101010100: ctl = 3'b100; 10'b0010101011: ctl = 3'b101;
        10'b0101010100: ctl = 3'b110; 10'b1010101011: ctl = 3'b111;
        default: ctl = 3'b000;
      endcase
    end
  endfunction
  // TMDS video decode (Section 5.4.4)
  function [7:0] vdec(input [9:0] w);
    reg [7:0] d; integer k;
    begin
      d = w[9] ? ~w[7:0] : w[7:0];
      vdec[0] = d[0];
      for (k = 1; k < 8; k = k + 1) vdec[k] = w[8] ? d[k] ^ d[k-1] : ~(d[k] ^ d[k-1]);
    end
  endfunction
  // BCH ECC, generator 1 + x^6 + x^7 + x^8, bits fed LSB first
  function [7:0] ecc(input [63:0] bits, input integer n);
    reg [7:0] e; integer k; reg fb;
    begin
      e = 8'd0;
      for (k = 0; k < n; k = k + 1) begin
        fb = e[0] ^ bits[k];
        e = {1'b0, e[7:1]};
        if (fb) e = e ^ 8'b10000011;
      end
      ecc = e;
    end
  endfunction

  // one line's worth of words, captured at the encoders' outputs
  wire [9:0] w0 = dut.tmds_word[0], w1 = dut.tmds_word[1], w2 = dut.tmds_word[2];
  // A word leaves the encoder three registers after its cx/cy (the input
  // register, the mode register, the encoder's own); seen from a clock edge,
  // which reads the state after the previous one, that is cxd[2].
  reg [10:0] cxd [0:3];
  reg [9:0]  cyd [0:3];
  reg [7:0] rd [0:3], gd [0:3], bd [0:3];
  integer dk;
  always @(posedge clk) begin
    for (dk = 3; dk > 0; dk = dk - 1) begin
      cxd[dk] <= cxd[dk-1]; cyd[dk] <= cyd[dk-1]; rd[dk] <= rd[dk-1]; gd[dk] <= gd[dk-1]; bd[dk] <= bd[dk-1];
    end
    cxd[0] <= cx; cyd[0] <= cy; rd[0] <= r; gd[0] <= g; bd[0] <= b;
  end

  // island reassembly
  reg [9:0] prev0 [0:15], prev1 [0:15], prev2 [0:15];   // last few words, for preambles
  integer state = 0;               // 0 control/video, 1 in island
  integer pix = 0, npk = 0;
  reg [31:0] hdr;
  reg [63:0] sp [0:3];
  integer nacr = 0, nasp = 0, navi = 0, nspd = 0, naif = 0, nnull = 0, nisl = 0;
  integer got = 0, frame_samples = 0;
  reg [15:0] rec [0:8191];            // the samples received, in order
  reg [19:0] n_val, cts_val;
  reg [7:0] byte_;
  integer sum, j, s;
  reg [23:0] smp;

  task packet_done;
    begin
      if (ecc({32'd0, hdr}, 24) !== hdr[31:24]) fail("header ECC");
      for (j = 0; j < 4; j = j + 1) if (ecc(sp[j], 56) !== sp[j][63:56]) fail("subpacket ECC");
      case (hdr[7:0])
        8'h00: nnull = nnull + 1;
        8'h01: begin
          nacr = nacr + 1;
          // SB0..SB6 = 0, CTS[19:16], CTS[15:8], CTS[7:0], N[19:16], N[15:8], N[7:0]
          cts_val = {sp[0][11:8], sp[0][23:16], sp[0][31:24]};
          n_val   = {sp[0][35:32], sp[0][47:40], sp[0][55:48]};
          if (n_val != 20'd6144) fail("ACR N");
          if (nacr > 1 && cts_val != CTS_WANT) begin
            if (fails < 20) $display("      CTS = %0d", cts_val); fail("ACR CTS");
          end
        end
        8'h02: begin
          nasp = nasp + 1;
          for (j = 0; j < 4; j = j + 1)
            if (hdr[8 + j]) begin            // sample present
              smp = sp[j][23:0];             // left: the top 16 of bits 0..23
              rec[got] = smp[23:8];
              if (sp[j][47:32] !== sp[j][23:8]) fail("right != left");
              got = got + 1; frame_samples = frame_samples + 1;
            end
        end
        8'h82, 8'h83, 8'h84: begin
          if (hdr[7:0] == 8'h82) navi = navi + 1;
          if (hdr[7:0] == 8'h83) nspd = nspd + 1;
          if (hdr[7:0] == 8'h84) naif = naif + 1;
          // checksum: the three header bytes and all 28 body bytes add to 0
          sum = hdr[7:0] + hdr[15:8] + hdr[23:16];
          for (j = 0; j < 4; j = j + 1)
            for (s = 0; s < 7; s = s + 1) sum = sum + sp[j][s*8 +: 8];
          if (sum[7:0] != 8'd0) fail("InfoFrame checksum");
        end
        default: begin if (fails < 20) $display("      type %h", hdr[7:0]); fail("unknown packet type"); end
      endcase
    end
  endtask

  integer t4_0, t4_1, t4_2;
  // check from the first whole frame on: the one under way at reset is not
  reg started = 1'b0;
  always @(posedge clk) if (cxd[2] == H_TOTAL - 1 && cyd[2] == V_TOTAL - 1) started <= 1'b1;
  always @(posedge clk) if (started) begin
    lx = cxd[2]; ly = cyd[2];
    for (k = 15; k > 0; k = k - 1) begin prev0[k] = prev0[k-1]; prev1[k] = prev1[k-1]; prev2[k] = prev2[k-1]; end
    prev0[0] = w0; prev1[0] = w1; prev2[0] = w2;
    t4_0 = terc4(w0); t4_1 = terc4(w1); t4_2 = terc4(w2);

    if (lx < H_ACTIVE && ly < V_ACTIVE) begin
      if (vdec(w2) !== rd[2] || vdec(w1) !== gd[2] || vdec(w0) !== bd[2]) fail("pixel");
    end
    // the video guard band: lanes 0/2 1011001100, lane 1 0100110011, 2 px
    if ((lx == H_TOTAL - 2 || lx == H_TOTAL - 1) && (ly == V_TOTAL - 1 || ly < V_ACTIVE - 1)) begin
      if (w0 !== 10'b1011001100 || w1 !== 10'b0100110011 || w2 !== 10'b1011001100) fail("video guard");
      // 8 px of video preamble before it: CTL0..3 = 1,0,0,0 (lane 1 = 01, lane 2 = 00)
      if (lx == H_TOTAL - 2)
        for (k = 1; k <= 8; k = k + 1)
          if (ctl(prev1[k]) !== 3'b101 || ctl(prev2[k]) !== 3'b100) fail("video preamble");
    end

    case (state)
      0: if (w1 === 10'b0100110011 && w2 === 10'b0100110011 && t4_0 < 16) begin
           // leading island guard: lanes 1, 2 = 0100110011, lane 0 TERC4 of {1,1,v,h}
           // (two of them; enter on the second)
           // (the trailing guard looks the same: require the preamble before)
           if (prev1[1] === 10'b0100110011 && ctl(prev1[2]) != 3'b000) begin
             for (k = 2; k <= 9; k = k + 1)
               if (ctl(prev1[k]) !== 3'b101 || ctl(prev2[k]) !== 3'b101) fail("island preamble");
             state = 1; pix = 0; npk = 0; nisl = nisl + 1;
           end
         end
      1: if (w1 === 10'b0100110011 && w2 === 10'b0100110011) begin
           state = 0;                               // trailing guard
           if (pix != 0) fail("island ends mid-packet");
         end else begin
           if (t4_0 >= 16 || t4_1 >= 16 || t4_2 >= 16) fail("not TERC4 in island");
           if (pix == 0) begin hdr = 32'd0; for (j = 0; j < 4; j = j + 1) sp[j] = 64'd0; end
           hdr[pix] = t4_0[2];
           if (t4_0[3] !== (npk != 0 || pix != 0)) fail("lane 0 bit 3");
           for (j = 0; j < 4; j = j + 1) begin
             sp[j][2*pix]     = t4_1[j];
             sp[j][2*pix + 1] = t4_2[j];
           end
           pix = pix + 1;
           if (pix == 32) begin packet_done; pix = 0; npk = npk + 1; end
         end
    endcase

    if (lx == H_ACTIVE - 1 && ly == V_ACTIVE - 1) begin
      $display("frame end at %0d ms: %0d islands, packets: %0d ACR, %0d audio, %0d AVI, %0d SPD, %0d AIF, %0d null; %0d samples this frame",
               $time / 1_000_000, nisl, nacr, nasp, navi, nspd, naif, nnull, frame_samples);
      frame_samples = 0;
    end
  end

  initial begin
    // let the audio path fill, then run FRAMES frames
    #((FRAMES + 1) * 20_708_000 + 1_000_000);
    // the received run must be one unbroken stretch of what was made: find
    // the offset where every sample matches (none lost, none repeated)
    begin : align
      integer o, i, best, bestn, n;
      best = -1; bestn = 0;
      for (o = 0; o + got <= nmade; o = o + 1) begin
        n = 0;
        for (i = 0; i < got; i = i + 1) if (rec[i] === made[o + i]) n = n + 1;
        if (n > bestn) begin bestn = n; best = o; end
      end
      $display("samples: %0d made, %0d received; best alignment at %0d matches %0d of them", nmade, got, best, bestn);
      if (bestn != got) fail("samples lost, repeated or changed");
      if (nmade - (best + got) > 8) fail("samples stuck at the end");
    end
    $display("CTS last seen %0d, N %0d", cts_val, n_val);
    begin : level   // the 1 kHz square: well above silence, never clipped
      integer i, mn, mx, v;
      mn = 32767; mx = -32768;
      for (i = nmade / 2; i < nmade; i = i + 1) begin
        v = $signed(made[i]); if (v < mn) mn = v; if (v > mx) mx = v;
      end
      $display("beeper level: %0d .. %0d", mn, mx);
      if (mx < 4000 || mn > -4000 || mx >= 32767 || mn <= -32768) fail("beeper level");
    end
    if (nacr < 10) fail("too few ACR packets");
    if (navi < FRAMES - 1 || nspd < FRAMES - 1 || naif < FRAMES - 1) fail("InfoFrames missing");
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
  end
endmodule
`default_nettype wire
