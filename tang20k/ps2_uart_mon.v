// -----------------------------------------------------------------------------
// PS/2 keyboard monitor over the board's USB serial port (debug builds only).
//
// Prints, at 115200 8N1 on the Tang Nano 20K's BL616 UART (FPGA pin 69 ->
// /dev/ttyUSB1 on the PC):
//
//   1C F0 1C            every byte ps2_rx accepted, as hex
//   !                   a frame ps2_rx rejected (parity or stop bit)
//   K 0000000020 kd 1E e 0021
//                       once a second: the 40 Spectrum keys held (bit
//                       row*5+col, hex), the AND of KD5..KD1 over that
//                       second -- a 0 bit means the CPU's row select reached
//                       a held key's column at least once -- and the number
//                       of PS/2 CLK falling edges in that second (11 a byte)
//
// A logic analyser on the keyboard path, in effect, readable without an LED
// table.  Bytes wait in a small FIFO while the transmitter is busy.
// -----------------------------------------------------------------------------
`default_nettype none

module ps2_uart_mon #(
    parameter integer CLK_HZ = 135_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire        clk,
    input  wire [7:0]  code,
    input  wire        valid,
    input  wire        err,
    input  wire [39:0] down,
    input  wire [4:0]  kd,
    input  wire        clk_fall,    // one pulse per PS/2 CLK falling edge
    output reg         tx = 1'b1
);
  // --- transmitter: one character at a time --------------------------------
  localparam integer DIV = (CLK_HZ + BAUD / 2) / BAUD;
  reg [15:0] baud = 16'd0;
  reg [9:0]  shreg = 10'h3FF;
  reg [3:0]  nbits = 4'd0;
  wire       tx_idle = (nbits == 4'd0);
  reg        send = 1'b0;
  reg [7:0]  ch = 8'h00;
  always @(posedge clk) begin
    if (tx_idle) begin
      if (send) begin shreg <= {1'b1, ch, 1'b0}; nbits <= 4'd10; baud <= DIV - 1; end
    end else if (baud == 0) begin
      tx <= shreg[0]; shreg <= {1'b1, shreg[9:1]}; nbits <= nbits - 4'd1; baud <= DIV - 1;
    end else
      baud <= baud - 16'd1;
  end

  // --- event FIFO: {err, byte} --------------------------------------------
  reg [8:0] fifo [0:15];
  reg [3:0] wp = 4'd0, rp = 4'd0;
  wire      empty = (wp == rp);
  always @(posedge clk)
    if (valid || err) begin fifo[wp] <= {err, code}; wp <= wp + 4'd1; end

  // --- once-a-second status snapshot --------------------------------------
  reg [27:0] tick = 28'd0;
  reg [4:0]  kd_and = 5'h1F;
  reg [39:0] snap_down = 40'd0;
  reg [4:0]  snap_kd = 5'h1F;
  reg [15:0] edges = 16'd0, snap_edges = 16'd0;
  reg        status_due = 1'b0, status_take = 1'b0;
  always @(posedge clk) begin
    if (tick == CLK_HZ - 1) begin
      tick <= 28'd0; snap_down <= down; snap_kd <= kd_and & kd; kd_and <= 5'h1F;
      snap_edges <= edges; edges <= 16'd0;
      status_due <= 1'b1;
    end else begin
      tick <= tick + 28'd1; kd_and <= kd_and & kd;
      if (clk_fall && edges != 16'hFFFF) edges <= edges + 16'd1;
      if (status_take) status_due <= 1'b0;
    end
  end

  // --- formatter -----------------------------------------------------------
  function [7:0] hex(input [3:0] n);
    hex = (n < 4'd10) ? 8'h30 + n : 8'h37 + n;
  endfunction
  // A message is up to 27 characters, built into a buffer then sent.
  reg [7:0] msg [0:26];
  reg [4:0] mlen = 5'd0, mpos = 5'd0;
  reg       busy = 1'b0;
  reg [8:0] ev;
  integer i;
  always @(posedge clk) begin
    send <= 1'b0;
    status_take <= 1'b0;
    if (!busy) begin
      if (!empty) begin
        ev = fifo[rp]; rp <= rp + 4'd1;
        if (ev[8]) begin msg[0] <= "!"; msg[1] <= " "; mlen <= 5'd2; end
        else begin msg[0] <= hex(ev[7:4]); msg[1] <= hex(ev[3:0]); msg[2] <= " "; mlen <= 5'd3; end
        mpos <= 5'd0; busy <= 1'b1;
      end else if (status_due) begin
        status_take <= 1'b1;
        msg[0] <= 8'h0D; msg[1] <= 8'h0A; msg[2] <= "K"; msg[3] <= " ";
        for (i = 0; i < 10; i = i + 1) msg[4 + i] <= hex(snap_down[39 - 4*i -: 4]);
        msg[14] <= " "; msg[15] <= "k"; msg[16] <= "d"; msg[17] <= " ";
        msg[18] <= hex({3'b000, snap_kd[4]}); msg[19] <= hex(snap_kd[3:0]);
        msg[20] <= " "; msg[21] <= "e"; msg[22] <= " ";
        msg[23] <= hex(snap_edges[15:12]); msg[24] <= hex(snap_edges[11:8]);
        msg[25] <= hex(snap_edges[7:4]);   msg[26] <= hex(snap_edges[3:0]);
        mlen <= 5'd27; mpos <= 5'd0; busy <= 1'b1;
      end
    end else if (tx_idle && !send) begin
      if (mpos == mlen)
        busy <= 1'b0;
      else begin
        ch <= msg[mpos]; send <= 1'b1; mpos <= mpos + 5'd1;
      end
    end
  end
endmodule
`default_nettype wire
