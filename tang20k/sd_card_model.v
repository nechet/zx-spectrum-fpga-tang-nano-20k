// -----------------------------------------------------------------------------
// Behavioural microSD card, SPI mode -- simulation only.  Answers the commands
// sd_spi.v uses, like an SDHC card: CMD0, CMD8 (echo), CMD55/ACMD41 (busy for
// the first BUSY_LOOPS tries), CMD58 (OCR with CCS), CMD16, CMD17 (a sector
// from `image`, after a few FF bytes of access time).  Samples MOSI on SCK
// rising, changes MISO on SCK falling, like a real card.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module sd_card_model #(
    parameter IMAGE = "",               // $readmemh file, bytes; empty = pattern
    parameter integer SECTORS = 64,
    parameter integer BUSY_LOOPS = 3,
    parameter integer SDHC = 1
) (
    input  wire sck, cs_n, mosi,
    output reg  miso = 1'b1
);
  reg [7:0] image [0:SECTORS*512-1];
  integer i;
  initial begin
    for (i = 0; i < SECTORS*512; i = i + 1) image[i] = (i * 7 + (i >> 9)) & 8'hFF;
    if (IMAGE != "") $readmemh(IMAGE, image);
  end

  reg [7:0]  rx = 8'hFF;
  reg [2:0]  bitn = 3'd0;
  reg [47:0] cmd = 48'd0;
  reg [2:0]  ncmd = 3'd0;
  reg        in_cmd = 1'b0;
  reg        app = 1'b0, idle = 1'b1;
  integer    busy = 0;
  // Bytes queued for MISO
  reg [7:0]  q [0:1023];
  integer    qh = 0, qt = 0;
  reg [7:0]  tx = 8'hFF;
  integer    k;
  integer    ncmds = 0;

  task push(input [7:0] b); begin q[qt] = b; qt = qt + 1; end endtask

  always @(posedge cs_n) begin bitn = 0; in_cmd = 0; ncmd = 0; end

  always @(posedge sck) if (!cs_n) begin
    rx = {rx[6:0], mosi};
    bitn = bitn + 1;
    if (bitn == 0) begin                       // a whole byte
      if (!in_cmd && rx[7:6] == 2'b01 && qh == qt) begin in_cmd = 1; ncmd = 0; end
      if (in_cmd) begin
        cmd = {cmd[39:0], rx}; ncmd = ncmd + 1;
        if (ncmd == 6) begin in_cmd = 0; respond(cmd); end
      end
    end
  end

  task respond(input [47:0] c);
    reg [5:0] n; reg [31:0] arg; integer base;
    begin
      n = c[45:40]; arg = c[39:8]; ncmds = ncmds + 1;
      push(8'hFF);                             // NCR: one byte of thinking time
      if (app && n == 6'd41) begin
        app = 0;
        if (busy < BUSY_LOOPS) begin busy = busy + 1; push(8'h01); end
        else begin idle = 0; push(8'h00); end
      end else begin
        app = 0;
        case (n)
          6'd0:  begin idle = 1; push(8'h01); end
          6'd8:  begin push(8'h01); push(8'h00); push(8'h00); push(8'h01); push(arg[7:0]); end
          6'd55: begin app = 1; push(idle ? 8'h01 : 8'h00); end
          6'd58: begin push(idle ? 8'h01 : 8'h00); push(SDHC ? 8'hC0 : 8'h80); push(8'hFF); push(8'h80); push(8'h00); end
          6'd16: push(8'h00);
          6'd17: begin
                   base = SDHC ? arg * 512 : arg;
                   push(8'h00);
                   for (k = 0; k < 5; k = k + 1) push(8'hFF);   // access time
                   push(8'hFE);
                   for (k = 0; k < 512; k = k + 1) push(image[base + k]);
                   push(8'h12); push(8'h34);                    // CRC, ignored
                 end
          default: push(8'h04);                // illegal command
        endcase
      end
    end
  endtask

  // MISO: next queued byte, MSB first.  In SPI mode 0 a bit must be on the
  // wire before the rising edge that samples it, so each falling edge puts
  // out the *next* bit, and the eighth falling edge of a byte puts out bit 7
  // of the following byte.
  reg [2:0] fcnt = 3'd0;                       // falling edges in this byte
  always @(negedge sck) if (!cs_n) begin
    fcnt = fcnt + 1;
    if (fcnt == 0) begin
      if (qh != qt) begin tx = q[qh]; qh = qh + 1; if (qh == qt) begin qh = 0; qt = 0; end end
      else tx = 8'hFF;
      miso <= tx[7];
    end else
      miso <= tx[7 - fcnt];
  end
  always @(posedge cs_n) begin fcnt = 0; tx = 8'hFF; miso <= 1'b1; end
endmodule
`default_nettype wire
