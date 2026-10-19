// -----------------------------------------------------------------------------
// HDMI out with sound: hdmi_out.v plus the data islands that carry audio.
//
// A DVI link sends only two kinds of period: video (pixels) and control
// (blanking, carrying the two syncs).  HDMI adds a third, the data island,
// placed in the horizontal blanking: a burst of 32-pixel packets, each coded
// four bits per lane per pixel (TERC4) and protected by an ECC.  The packets
// used here, from hdl-util/hdmi (third_party/hdmi):
//   audio clock regeneration  N and CTS, so the monitor can rebuild 48 kHz
//                             from the pixel clock (CTS measured, not assumed)
//   audio samples             up to four stereo samples per packet
//   AVI / audio / product InfoFrames, once a field: what the stream contains
//
// The island timing is upstream hdmi.sv's, but driven by the scan doubler's
// own counters (cx, cy) instead of a timing generator of its own, because
// our rasters are not standard modes.  576p (896 x 624): 176 pixels of
// blanking hold four packets, and 48 kHz needs about 1.6 samples per 33 us
// line.  720p (1792 x 936, scan_tripler.v): 512 pixels would hold fifteen,
// for about 1.1 samples per 22 us line.  Islands are capped at MAX_ISLAND
// packets all the same: four is what the 576p build sends and monitors are
// known to take; with one sample packet needed per line, it is plenty.
//
// Timing: rgb, hsync_tx, vsync_tx arrive in the same clock as cx/cy (as the
// doubler makes them); they are registered once here, which is the one-clock
// lag upstream's logic expects of the pixel data.
// -----------------------------------------------------------------------------
`default_nettype none

module hdmi_audio_out #(
    parameter TRUE_LVDS     = 1,
    parameter H_ACTIVE      = 720,
    parameter H_TOTAL       = 896,
    parameter V_ACTIVE      = 576,
    parameter V_TOTAL       = 624,
    parameter VIDEO_ID_CODE = 17,           // 720x576p50 4:3, the nearest CEA mode
    parameter real VIDEO_RATE = 27.0E6,     // the pixel clock, for the CTS counter width
    parameter AUDIO_RATE    = 48000,
    parameter MAX_ISLAND    = 4             // packets an island at most (the spec allows 18)
) (
    input  wire        clk_pixel,
    input  wire        clk_x5,
    input  wire        reset,
    input  wire [10:0] cx,                  // raster position of this pixel
    input  wire [9:0]  cy,
    input  wire [7:0]  red,
    input  wire [7:0]  green,
    input  wire [7:0]  blue,
    input  wire        hsync_tx,            // already at the mode's polarity
    input  wire        vsync_tx,
    input  wire        clk_audio,           // AUDIO_RATE; samples taken on its rising edge
    input  wire [15:0] audio_l,
    input  wire [15:0] audio_r,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n);

  // one clock of lag on the pixel data and syncs (see the header)
  reg [23:0] rgb = 24'd0;
  reg hsync = 1'b0, vsync = 1'b0;
  always @(posedge clk_pixel) begin
    rgb <= {red, green, blue}; hsync <= hsync_tx; vsync <= vsync_tx;
  end

  // --- periods, Section 5.2 (upstream hdmi.sv, cx/cy from outside) ----------
  reg video_data_period = 1'b0;
  always @(posedge clk_pixel)
    video_data_period <= (cx < H_ACTIVE) && (cy < V_ACTIVE);

  // the video preamble and leading guard band just before each active line
  reg video_guard = 1'b0, video_preamble = 1'b0;
  wire before_active_line = (cy == V_TOTAL - 1) || (cy < V_ACTIVE - 1);
  always @(posedge clk_pixel) begin
    video_guard    <= cx >= H_TOTAL - 2  && cx < H_TOTAL     && before_active_line;
    video_preamble <= cx >= H_TOTAL - 10 && cx < H_TOTAL - 2 && before_active_line;
  end

  // Section 5.2.3.1: as many packets as fit between the active video and the
  // next line's video preamble, with the guard bands and minimum control
  // periods around them
  localparam MAX_PACKETS = (H_TOTAL - H_ACTIVE - 2 - 8 - 4 - 2 - 2 - 8 - 4) / 32;
  localparam NUM_PACKETS = MAX_PACKETS > MAX_ISLAND ? MAX_ISLAND : MAX_PACKETS;
  localparam DI_START = H_ACTIVE + 14;                 // first island pixel
  localparam DI_END   = DI_START + NUM_PACKETS * 32;   // one past the last

  wire data_island_now = NUM_PACKETS > 0 && cx >= DI_START && cx < DI_END;
  wire packet_enable   = data_island_now && cx[4:0] == DI_START[4:0];   // each packet's first pixel

  reg data_island_guard = 1'b0, data_island_preamble = 1'b0, data_island_period = 1'b0;
  reg data_island_first = 1'b0;
  always @(posedge clk_pixel) begin
    data_island_first    <= cx == DI_START;
    data_island_guard    <= NUM_PACKETS > 0 &&
                            ((cx >= H_ACTIVE + 12 && cx < DI_START) || (cx >= DI_END && cx < DI_END + 2));
    data_island_preamble <= NUM_PACKETS > 0 && cx >= H_ACTIVE + 4 && cx < H_ACTIVE + 12;
    data_island_period   <= data_island_now;
  end

  // --- the packets ------------------------------------------------------------
  wire [23:0] header;
  wire [55:0] sub [3:0];
  wire [4:0]  packet_pixel_counter;
  wire [8:0]  packet_data;
  wire        video_field_end = (cx == H_ACTIVE - 1) && (cy == V_ACTIVE - 1);
  wire [15:0] audio_sample_word [1:0];
  assign audio_sample_word[0] = audio_l;
  assign audio_sample_word[1] = audio_r;

  packet_picker #(
      .VIDEO_ID_CODE (VIDEO_ID_CODE),
      .VIDEO_RATE    (VIDEO_RATE),
      .IT_CONTENT    (1'b1),
      .AUDIO_RATE    (AUDIO_RATE),
      .AUDIO_BIT_WIDTH (16),
      .VENDOR_NAME   ({"Krasnod", 8'd0}),
      .PRODUCT_DESCRIPTION ({"Krasnodar-48", 32'd0}),
      .SOURCE_DEVICE_INFORMATION (8'h08)    // game
  ) picker (
      .clk_pixel (clk_pixel), .clk_audio (clk_audio), .reset (reset),
      .video_field_end (video_field_end), .packet_enable (packet_enable),
      .packet_pixel_counter (packet_pixel_counter),
      .audio_sample_word (audio_sample_word), .header (header), .sub (sub));

  packet_assembler assembler (
      .clk_pixel (clk_pixel), .reset (reset), .data_island_period (data_island_period),
      .header (header), .sub (sub), .packet_data (packet_data),
      .counter (packet_pixel_counter));

  // --- what each lane carries this pixel ----------------------------------------
  reg [2:0]  mode = 3'd0;
  reg [23:0] video_data = 24'd0;
  reg [5:0]  control_data = 6'd0;
  reg [11:0] data_island_data = 12'd0;
  always @(posedge clk_pixel)
    if (reset) begin
      mode <= 3'd2; video_data <= 24'd0; control_data <= 6'd0; data_island_data <= 12'd0;
    end else begin
      mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 :
              video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
      video_data <= rgb;
      // CTL3..0: 0101 before a data island, 0001 before video
      control_data <= {1'b0, data_island_preamble, 1'b0, video_preamble | data_island_preamble,
                       vsync, hsync};
      data_island_data[11:4] <= packet_data[8:1];
      // 0 on an island's first pixel, 1 on the rest (Section 5.2.3.4;
      // upstream sends cx != 0, which is 1 throughout)
      data_island_data[3]    <= !data_island_first;
      data_island_data[2]    <= packet_data[0];
      data_island_data[1:0]  <= {vsync, hsync};
    end

  wire [9:0] tmds_word [2:0];
  genvar i;
  generate
    for (i = 0; i < 3; i = i + 1) begin : enc
      tmds_channel #(.CN(i)) ch (
          .clk_pixel        (clk_pixel),
          .video_data       (video_data[i*8+7 : i*8]),
          .data_island_data (data_island_data[i*4+3 : i*4]),
          .control_data     (control_data[i*2+1 : i*2]),
          .mode             (mode),
          .tmds             (tmds_word[i]));
    end
  endgenerate

  // --- serialisers and pins: as hdmi_out.v ------------------------------------
  wire [2:0] tmds_serial;
  generate
    for (i = 0; i < 3; i = i + 1) begin : ser
      OSER10 oser (
          .Q  (tmds_serial[i]),
          .D0 (tmds_word[i][0]), .D1 (tmds_word[i][1]),
          .D2 (tmds_word[i][2]), .D3 (tmds_word[i][3]),
          .D4 (tmds_word[i][4]), .D5 (tmds_word[i][5]),
          .D6 (tmds_word[i][6]), .D7 (tmds_word[i][7]),
          .D8 (tmds_word[i][8]), .D9 (tmds_word[i][9]),
          .PCLK (clk_pixel), .FCLK (clk_x5), .RESET (reset));
    end
  endgenerate

  wire tmds_clk_serial;
  OSER10 oser_clk (
      .Q  (tmds_clk_serial),
      .D0 (1'b1), .D1 (1'b1), .D2 (1'b1), .D3 (1'b1), .D4 (1'b1),
      .D5 (1'b0), .D6 (1'b0), .D7 (1'b0), .D8 (1'b0), .D9 (1'b0),
      .PCLK (clk_pixel), .FCLK (clk_x5), .RESET (reset));

  generate
    if (TRUE_LVDS) begin : tlvds
      TLVDS_OBUF tmds_buf [3:0] (
          .I  ({tmds_clk_serial, tmds_serial}),
          .O  ({tmds_clk_p, tmds_d_p}),
          .OB ({tmds_clk_n, tmds_d_n}));
    end else begin : elvds
      ELVDS_OBUF tmds_buf [3:0] (
          .I  ({tmds_clk_serial, tmds_serial}),
          .O  ({tmds_clk_p, tmds_d_p}),
          .OB ({tmds_clk_n, tmds_d_n}));
    end
  endgenerate
endmodule
`default_nettype wire
