// -----------------------------------------------------------------------------
// TMDS encode + 10:1 serialise + differential output.  The back end shared by
// the colour-bar test and the scan doubler.
// -----------------------------------------------------------------------------
`default_nettype none

module hdmi_out #(
    parameter TRUE_LVDS = 0      // 1: true LVDS (the Tang Nano 20K)  0: emulated (simulation stubs)
) (
    input  wire        clk_pixel,
    input  wire        clk_x5,
    input  wire        reset,
    input  wire [7:0]  red,
    input  wire [7:0]  green,
    input  wire [7:0]  blue,
    input  wire        hsync_tx,      // already at the mode's polarity
    input  wire        vsync_tx,
    input  wire        active,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n);

  reg [2:0]  mode         = 3'd0;
  reg [23:0] video_data   = 24'd0;
  reg [5:0]  control_data = 6'd0;
  always @(posedge clk_pixel)
    if (reset) begin
      mode <= 3'd0; video_data <= 24'd0; control_data <= 6'd0;
    end else begin
      mode         <= active ? 3'd1 : 3'd0;
      video_data   <= {red, green, blue};
      control_data <= {4'b0000, vsync_tx, hsync_tx};
    end

  wire [9:0] tmds_word [2:0];
  genvar i;
  generate
    for (i = 0; i < 3; i = i + 1) begin : enc
      tmds_channel #(.CN(i)) ch (
          .clk_pixel        (clk_pixel),
          .video_data       (video_data[i*8+7 : i*8]),
          .data_island_data (4'd0),
          .control_data     (control_data[i*2+1 : i*2]),
          .mode             (mode),
          .tmds             (tmds_word[i]));
    end
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
  wire [2:0] tmds_serial;

  // The clock lane through a serialiser as well, sending 0000011111 -- one
  // period of clk_pixel, edge-aligned with the data words.  Driving the pin
  // from clk_pixel directly routes a clock net through general fabric to the
  // I/O, so its phase and jitter vary with placement: on the 20K the colour
  // bars synced but the full design did not.
  wire tmds_clk_serial;
  OSER10 oser_clk (
      .Q  (tmds_clk_serial),
      .D0 (1'b1), .D1 (1'b1), .D2 (1'b1), .D3 (1'b1), .D4 (1'b1),
      .D5 (1'b0), .D6 (1'b0), .D7 (1'b0), .D8 (1'b0), .D9 (1'b0),
      .PCLK (clk_pixel), .FCLK (clk_x5), .RESET (reset));

  // The Tang Nano 20K's HDMI pins are real LVDS pairs (LVDS25): TLVDS_OBUF.
  // ELVDS_OBUF (emulated LVDS) has the same ports; it is what the simulation
  // stubs model, so the choice is a parameter.
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
