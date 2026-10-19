// -----------------------------------------------------------------------------
// SD card test top (gowin_sdtest): initialise the microSD card and print what
// is on it to the USB serial port (/dev/ttyUSB1, 115200 8N1).
//
//   SD init: OK SDHC                 or  SD init: ERROR 1 (see sd_spi err_code)
//   sector 00000000                  the MBR: partition table at 1BE
//   000: EB 58 90 ...  (16 lines of 32 bytes)
//   sector 00002000                  if partition 1 is FAT32 (type 0B/0C):
//   ...                              its first sector, the volume boot record
//
// Button S1 (pin 88) runs it again -- swap cards without reloading.
// LEDs (active low): 0 card ready, 1 error, 5 heartbeat.
// -----------------------------------------------------------------------------
`default_nettype none

module sd_dump (
    input  wire       clk,          // 27 MHz
    input  wire       rst_i,        // button S1, active high
    output wire [5:0] led,
    output wire       sd_clk, sd_cmd, sd_dat3,
    input  wire       sd_dat0,
    output wire       uart_tx
);
  wire clk_x5, lock;
`ifdef SIM
  reg sclk = 1'b0; always #3.7037 sclk = ~sclk;
  assign clk_x5 = sclk; assign lock = 1'b1;
`else
  pll_135 pll (.clkin(clk), .clkout(clk_x5), .lock(lock));
`endif

  // --- button: synchronise, start on power-up and on every press ----------
  reg [2:0]  btn = 3'b000;
  reg [21:0] boot = `ifdef SIM 22'h3FFF00 `else 22'd0 `endif;
  reg        start = 1'b0;
  always @(posedge clk_x5) begin
    btn   <= {btn[1:0], rst_i};
    start <= 1'b0;
    if (lock && !(&boot)) begin boot <= boot + 22'd1; if (boot == 22'h3FFFFE) start <= 1'b1; end
    if (btn[2:1] == 2'b01) start <= 1'b1;
  end

  // --- the card ---------------------------------------------------------------
  reg         rd = 1'b0;
  reg  [31:0] lba = 32'd0;
  wire [7:0]  dout; wire dout_valid, ready, err, sdhc; wire [3:0] err_code;
  sd_spi #(.CLK_HZ(135_000_000)) sd (
      .clk(clk_x5), .start(start), .sd_sck(sd_clk), .sd_cs_n(sd_dat3), .sd_mosi(sd_cmd),
      .sd_miso(sd_dat0), .rd(rd), .lba(lba), .dout(dout), .dout_valid(dout_valid),
      .ready(ready), .err(err), .err_code(err_code), .sdhc(sdhc));

  // --- sector buffer -----------------------------------------------------------
  reg [7:0] buf_mem [0:511];
  reg [8:0] wa = 9'd0;
  always @(posedge clk_x5)
    if (rd) wa <= 9'd0;                                  // a new sector starts at 0
    else if (dout_valid) begin buf_mem[wa] <= dout; wa <= wa + 9'd1; end
  reg [8:0] ra = 9'd0;
  reg [7:0] rb = 8'h00;
  always @(posedge clk_x5) rb <= buf_mem[ra];

  // --- serial out --------------------------------------------------------------
  reg  [7:0] ch = 8'h00;
  reg        send = 1'b0;
  wire       tx_idle;
  uart_tx #(.CLK_HZ(135_000_000)) tx (.clk(clk_x5), .data(ch), .send(send), .idle(tx_idle), .tx(uart_tx));

  function [7:0] hexc(input [3:0] n);
    hexc = (n < 4'd10) ? 8'h30 + n : 8'h37 + n;
  endfunction

  // Text: a few fixed strings, picked by number; character i, or 0 past the
  // end.  A string literal is right-aligned in a wider reg, so character i of
  // an L-character string is byte L-1-i counting from the right.  (\015 is
  // CR: plain Verilog strings have \n but no \r.)
  function [7:0] text(input [2:0] m, input [4:0] i);
    reg [8*24-1:0] s;
    reg [4:0] len;
    begin
      case (m)
        3'd0:    begin s = "\015\nSD init: OK SDHC\015\n"; len = 5'd20; end
        3'd1:    begin s = "\015\nSD init: OK SDSC\015\n"; len = 5'd20; end
        3'd2:    begin s = "\015\nSD init: ERROR ";        len = 5'd17; end
        3'd3:    begin s = "\015\nsector ";                len = 5'd9;  end
        default: begin s = "\015\ndone\015\n";           len = 5'd8;  end
      endcase
      text = (i < len) ? s[8*(len - 1 - i) +: 8] : 8'h00;
    end
  endfunction

  // --- the sequence ------------------------------------------------------------
  localparam [3:0] Q_WAIT = 4'd0, Q_MSG = 4'd1, Q_ERRC = 4'd2, Q_RD = 4'd3, Q_RDW = 4'd4,
                   Q_LBA = 4'd5, Q_LINE = 4'd6, Q_BYTE = 4'd7, Q_NEXT = 4'd8, Q_STOP = 4'd9,
                   Q_MSGW = 4'd10;
  reg [3:0]  q = Q_WAIT, q_after = Q_WAIT;
  reg [2:0]  m = 3'd0;
  reg [4:0]  mi = 5'd0;
  reg [3:0]  k = 4'd0;              // digit index
  reg        second = 1'b0;         // 0: printing the MBR, 1: the partition's first sector
  reg [31:0] part = 32'd0;
  reg        part_ok = 1'b0;

  task putc(input [7:0] c); begin ch <= c; send <= 1'b1; end endtask

  always @(posedge clk_x5) begin
    send <= 1'b0;
    rd   <= 1'b0;
    if (start) begin q <= Q_WAIT; second <= 1'b0; end
    else case (q)
      Q_WAIT: if (err) begin m <= 3'd2; mi <= 5'd0; q_after <= Q_ERRC; q <= Q_MSG; end
              else if (ready) begin m <= sdhc ? 3'd0 : 3'd1; mi <= 5'd0; lba <= 32'd0; q_after <= Q_RD; q <= Q_MSG; end
      Q_MSG:  if (tx_idle && !send) begin
                if (text(m, mi) == 8'h00) q <= q_after;
                else begin putc(text(m, mi)); mi <= mi + 5'd1; end
              end
      Q_ERRC: if (tx_idle && !send) begin putc(hexc(err_code)); m <= 3'd4; mi <= 5'd0; q_after <= Q_STOP; q <= Q_MSGW; end
      Q_MSGW: if (tx_idle && !send) q <= Q_MSG;
      Q_RD:   if (ready) begin rd <= 1'b1; q <= Q_RDW; end
      Q_RDW:  if (err) begin m <= 3'd2; mi <= 5'd0; q_after <= Q_ERRC; q <= Q_MSG; end
              else if (ready && !rd) begin m <= 3'd3; mi <= 5'd0; k <= 4'd0; q_after <= Q_LBA; q <= Q_MSG; end
      Q_LBA:  if (tx_idle && !send) begin               // sector number, 8 hex digits
                if (k == 4'd8) begin ra <= 9'd0; k <= 4'd0; q <= Q_LINE; end
                else begin putc(hexc(lba[31 - 4*k -: 4])); k <= k + 4'd1; end
              end
      Q_LINE: if (tx_idle && !send) begin               // "\r\nOOO: "
                case (k)
                  4'd0: putc(8'h0D); 4'd1: putc(8'h0A);
                  4'd2: putc(hexc({3'b000, ra[8]})); 4'd3: putc(hexc(ra[7:4])); 4'd4: putc(hexc(ra[3:0]));
                  4'd5: putc(":"); default: putc(" ");
                endcase
                if (k == 4'd6) begin k <= 4'd0; q <= Q_BYTE; end else k <= k + 4'd1;
              end
      Q_BYTE: if (tx_idle && !send) begin               // "XX " (rb follows ra one clock later)
                case (k)
                  4'd0: putc(hexc(rb[7:4])); 4'd1: putc(hexc(rb[3:0])); default: putc(" ");
                endcase
                if (k == 4'd2) begin k <= 4'd0; q <= Q_NEXT; end else k <= k + 4'd1;
              end
      Q_NEXT: begin
                // While on the MBR, pick up partition 1: type at 1C2, LBA at 1C6.
                if (!second && ra == 9'h1C2) part_ok <= (rb == 8'h0B || rb == 8'h0C);
                if (!second && ra >= 9'h1C6 && ra <= 9'h1C9) part <= {rb, part[31:8]};
                if (ra == 9'd511) begin
                  if (!second && part_ok) begin second <= 1'b1; lba <= part; q <= Q_RD; end
                  else begin m <= 3'd4; mi <= 5'd0; q_after <= Q_STOP; q <= Q_MSG; end
                end else begin
                  ra <= ra + 9'd1;
                  q <= (ra[4:0] == 5'd31) ? Q_LINE : Q_BYTE;
                end
              end
      Q_STOP: ;
      default: q <= Q_WAIT;
    endcase
  end

  // --- LEDs ----------------------------------------------------------------------
  reg [26:0] beat = 27'd0;
  always @(posedge clk_x5) beat <= beat + 27'd1;
  assign led = ~{beat[26], 3'b000, err, ready};
endmodule
`default_nettype wire
