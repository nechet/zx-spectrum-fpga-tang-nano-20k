// -----------------------------------------------------------------------------
// microSD card reader, SPI mode: initialise the card, then read 512-byte
// sectors on request.
//
// The card is a serial device with a tiny command language.  Every command
// is six bytes -- 01cccccc, a 32-bit argument, a CRC -- and the card answers
// with a one-byte status, R1 (0 = all well, bit 0 = "still initialising").
// Waking a card up is a fixed recipe from the SD specification:
//
//   >= 74 clocks with CS high       let the card's controller start
//   CMD0                            go to SPI mode, "idle"         R1 = 01
//   CMD8   arg 1AA                  are you a v2 card? (echoes AA)  R1 = 01
//   CMD55 + ACMD41 (HCS bit)        start initialising -- repeat until R1 = 00
//   CMD58                           read OCR; bit 30 = SDHC/SDXC (block-addressed)
//   CMD16  512                      (old byte-addressed cards only) block size
//
// then reading a sector is
//
//   CMD17  sector (SDHC) or sector*512 (SDSC)               R1 = 00
//   wait for the start token FE, 512 data bytes, 2 CRC bytes (ignored)
//
// Initialisation runs at ~400 kHz, as the spec demands; reads at CLK_HZ /
// (2 * FAST_HALF) -- 13.5 MHz from the board's 27 MHz with FAST_HALF = 1.
//
// Two layers, as in a TTL design: a byte shifter (one SPI byte out and in at
// a time, like a '595 and a '165 sharing a clock) and a sequencer that walks
// the recipe above, one byte per step.
//
// Interface: when `ready`, pulse `rd` with `lba`; the sector's bytes come out
// on `dout` with a one-clock `dout_valid` each, then `ready` returns.  `err`
// latches if the card does not answer; `err_code` says where it stopped.
// -----------------------------------------------------------------------------
`default_nettype none

module sd_spi #(
    parameter integer CLK_HZ    = 135_000_000,
    parameter integer SLOW_HZ   = 400_000,
    parameter integer FAST_HALF = 4             // system clocks per SCK half-period
) (
    input  wire        clk,
    input  wire        start,       // pulse: (re)initialise the card
    output reg         sd_sck  = 1'b0,
    output reg         sd_cs_n = 1'b1,
    output reg         sd_mosi = 1'b1,
    input  wire        sd_miso,
    input  wire        rd,
    input  wire [31:0] lba,
    output reg  [7:0]  dout = 8'h00,
    output reg         dout_valid = 1'b0,
    output wire        ready,
    output reg         err = 1'b0,
    output reg  [3:0]  err_code = 4'h0,
    output reg         sdhc = 1'b0
);
  localparam integer SLOW_HALF = (CLK_HZ + SLOW_HZ) / (2 * SLOW_HZ);

  // --- byte shifter: SPI mode 0, MSB first --------------------------------
  // MOSI changes on SCK falling, MISO is sampled on SCK rising.
  reg        fast = 1'b0;
  reg        go = 1'b0;             // pulse: shift go_byte out, a byte in
  reg  [7:0] go_byte = 8'hFF;
  reg        busy = 1'b0, done = 1'b0;
  reg  [7:0] tsh = 8'hFF, rsh = 8'hFF;
  reg  [2:0] bn = 3'd0;
  reg  [8:0] dc = 9'd0;
  wire [8:0] half = fast ? FAST_HALF[8:0] : SLOW_HALF[8:0];
  // MISO is sampled straight from the pin on the clock that raises SCK: the
  // card changed it after the previous falling edge, a whole half-period
  // ago.  (Through an extra register it would be one half-period stale --
  // the previous bit -- when FAST_HALF = 1.)
  always @(posedge clk) begin
    done   <= 1'b0;
    if (go && !busy) begin
      busy <= 1'b1; tsh <= go_byte; sd_mosi <= go_byte[7]; bn <= 3'd0; dc <= 9'd0;
    end else if (busy) begin
      if (dc == half - 9'd1) begin
        dc <= 9'd0;
        if (!sd_sck) begin
          sd_sck <= 1'b1; rsh <= {rsh[6:0], sd_miso};
        end else begin
          sd_sck <= 1'b0;
          if (bn == 3'd7) begin busy <= 1'b0; done <= 1'b1; sd_mosi <= 1'b1; end
          else begin bn <= bn + 3'd1; tsh <= {tsh[6:0], 1'b1}; sd_mosi <= tsh[6]; end
        end
      end else
        dc <= dc + 9'd1;
    end
  end

  // --- sequencer -----------------------------------------------------------
  localparam [4:0]
    S_OFF   = 5'd0,  S_PWR  = 5'd1,  S_WAKE = 5'd2,
    S_C0    = 5'd3,  S_C8   = 5'd4,  S_C8X  = 5'd5,  S_C55 = 5'd6,  S_A41 = 5'd7,
    S_C58   = 5'd8,  S_C58X = 5'd9,  S_C16  = 5'd10,
    S_IDLE  = 5'd11, S_C17  = 5'd12, S_TOK  = 5'd13, S_DATA = 5'd14, S_CRC = 5'd15,
    S_SEND  = 5'd16, S_R1   = 5'd17, S_GAP  = 5'd18, S_ERR  = 5'd19,
    S_CHK0  = 5'd20, S_CHK8 = 5'd21, S_CHK55 = 5'd22, S_CHK41 = 5'd23,
    S_CHK58 = 5'd24, S_CHK16 = 5'd25, S_CHK17 = 5'd26;
  reg [4:0]  st = S_OFF, ret = S_OFF;
  reg        wt = 1'b0;             // a byte is in flight
  reg [47:0] cmd = 48'hFF_FFFF_FFFF_FF;
  reg [2:0]  ci = 3'd0;             // command byte index
  reg [7:0]  r1 = 8'hFF;
  reg [31:0] xb = 32'd0;            // extra response bytes (R7, OCR)
  reg [3:0]  rc = 4'd0;             // R1 poll / extra byte count
  reg [9:0]  n = 10'd0;             // byte counter (wake clocks, data)
  reg [17:0] tries = 18'd0;         // ACMD41 retries, start-token polls
  reg [17:0] pwr = 18'd0;
  reg        v2 = 1'b0;

  assign ready = (st == S_IDLE);

  // Next command frame; CRC matters only for CMD0 and CMD8 in SPI mode.
  function [47:0] frame(input [5:0] c, input [31:0] arg);
    frame = {2'b01, c, arg, (c == 6'd0) ? 8'h95 : (c == 6'd8) ? 8'h87 : 8'h01};
  endfunction

  // Shift one byte; the result is in rsh when `done` pulses.
  task xfer(input [7:0] b);
    begin go <= 1'b1; go_byte <= b; wt <= 1'b1; end
  endtask

  task fail(input [3:0] code);
    begin err <= 1'b1; err_code <= code; sd_cs_n <= 1'b1; st <= S_ERR; end
  endtask

  // Send command c, then poll for R1, then continue at state nxt.
  task command(input [5:0] c, input [31:0] arg, input [4:0] nxt);
    begin cmd <= frame(c, arg); ci <= 3'd0; ret <= nxt; st <= S_GAP; end
  endtask

  always @(posedge clk) begin
    go <= 1'b0;
    dout_valid <= 1'b0;
    if (done) wt <= 1'b0;

    if (start) begin
      st <= S_PWR; pwr <= 18'd0; err <= 1'b0; err_code <= 4'h0; fast <= 1'b0;
      sd_cs_n <= 1'b1; wt <= 1'b0; sdhc <= 1'b0; v2 <= 1'b0;
    end else case (st)
      S_OFF, S_ERR: ;

      // ~1.9 ms for the card's supply to settle (2^18 clocks at 135 MHz)
      S_PWR:  begin pwr <= pwr + 18'd1; if (&pwr) begin n <= 10'd0; st <= S_WAKE; end end

      // 80 clocks with CS high and MOSI high
      S_WAKE: if (!wt && !go) begin
                if (n == 10'd10) command(6'd0, 32'd0, S_CHK0);
                else begin xfer(8'hFF); n <= n + 10'd1; end
              end

      // --- the command helper: gap byte, 6 command bytes, R1 polling -------
      // A byte with CS high between commands, as many cards want.
      S_GAP:  if (!wt && !go) begin
                if (sd_cs_n && ci == 3'd1) begin sd_cs_n <= 1'b0; ci <= 3'd0; st <= S_SEND; end
                else begin sd_cs_n <= 1'b1; xfer(8'hFF); ci <= 3'd1; end
              end
      S_SEND: if (!wt && !go) begin
                if (ci == 3'd6) begin rc <= 4'd0; st <= S_R1; end
                else begin xfer(cmd[47:40]); cmd <= {cmd[39:0], 8'hFF}; ci <= ci + 3'd1; end
              end
      S_R1:   if (done) begin
                if (!rsh[7]) begin r1 <= rsh; st <= ret; end
                else if (rc == 4'd10) begin r1 <= 8'hFF; st <= ret; end   // no answer
                else rc <= rc + 4'd1;
              end else if (!wt && !go) xfer(8'hFF);

      // --- initialisation ---------------------------------------------------
      S_CHK0: if (r1 == 8'h01) command(6'd8, 32'h0000_01AA, S_CHK8);
              else fail(4'h1);                                   // no card / no answer
      S_CHK8: if (r1 == 8'h01) begin v2 <= 1'b1; rc <= 4'd0; st <= S_C8X; end
              else if (r1[2]) begin v2 <= 1'b0; tries <= 18'd0; command(6'd55, 32'd0, S_CHK55); end // v1: illegal command
              else fail(4'h2);
      S_C8X:  if (done) begin                                    // R7: 4 more bytes
                xb <= {xb[23:0], rsh}; rc <= rc + 4'd1;
                if (rc == 4'd3) begin
                  if (rsh != 8'hAA) fail(4'h3);
                  else begin tries <= 18'd0; command(6'd55, 32'd0, S_CHK55); end
                end
              end else if (!wt && !go && rc != 4'd4) xfer(8'hFF);
      S_CHK55: if (r1[7:1] == 7'd0) command(6'd41, v2 ? 32'h4000_0000 : 32'd0, S_CHK41);
               else fail(4'h4);
      S_CHK41: if (r1 == 8'h00) begin
                 if (v2) command(6'd58, 32'd0, S_CHK58);
                 else command(6'd16, 32'd512, S_CHK16);
               end else if (r1 == 8'h01 && tries != 18'h3FFFF) begin
                 tries <= tries + 18'd1; command(6'd55, 32'd0, S_CHK55);
               end else fail(4'h5);                              // never left idle
      S_CHK58: if (r1 == 8'h00) begin rc <= 4'd0; st <= S_C58X; end
               else fail(4'h6);
      S_C58X: if (done) begin                                    // OCR: 4 bytes
                xb <= {xb[23:0], rsh}; rc <= rc + 4'd1;
                if (rc == 4'd3) begin
                  sdhc <= xb[22];                                // OCR bit 30
                  if (xb[22]) begin sd_cs_n <= 1'b1; fast <= 1'b1; st <= S_IDLE; end
                  else command(6'd16, 32'd512, S_CHK16);
                end
              end else if (!wt && !go && rc != 4'd4) xfer(8'hFF);
      S_CHK16: if (r1 == 8'h00) begin sd_cs_n <= 1'b1; fast <= 1'b1; st <= S_IDLE; end
               else fail(4'h7);

      // --- reading -----------------------------------------------------------
      S_IDLE: if (rd) command(6'd17, sdhc ? lba : {lba[22:0], 9'd0}, S_CHK17);
      S_CHK17: if (r1 == 8'h00) begin tries <= 18'd0; st <= S_TOK; end
               else fail(4'h8);
      S_TOK:  if (done) begin
                if (rsh == 8'hFE) begin n <= 10'd0; st <= S_DATA; end
                else if (rsh != 8'hFF) fail(4'h9);               // data error token
                else if (tries == 18'h3FFFF) fail(4'hA);         // card never answered
                else tries <= tries + 18'd1;
              end else if (!wt && !go) xfer(8'hFF);
      S_DATA: if (done) begin
                dout <= rsh; dout_valid <= 1'b1; n <= n + 10'd1;
                if (n == 10'd511) begin n <= 10'd0; st <= S_CRC; end
              end else if (!wt && !go) xfer(8'hFF);
      S_CRC:  if (done) begin
                n <= n + 10'd1;
                if (n == 10'd1) begin sd_cs_n <= 1'b1; st <= S_IDLE; end
              end else if (!wt && !go) xfer(8'hFF);
      default: st <= S_OFF;
    endcase
  end
endmodule
`default_nettype wire
