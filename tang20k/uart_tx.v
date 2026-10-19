// -----------------------------------------------------------------------------
// UART transmitter, 8N1.  Pulse `send` with `data` while `idle`; the byte goes
// out LSB first between a start bit (0) and a stop bit (1) -- a 10-bit shift
// register clocked by a baud-rate divider.
// -----------------------------------------------------------------------------
`default_nettype none

module uart_tx #(
    parameter integer CLK_HZ = 135_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire [7:0] data,
    input  wire       send,
    output wire       idle,
    output reg        tx = 1'b1
);
  localparam integer DIV = (CLK_HZ + BAUD / 2) / BAUD;
  reg [15:0] baud = 16'd0;
  reg [9:0]  sh = 10'h3FF;
  reg [3:0]  nbits = 4'd0;
  assign idle = (nbits == 4'd0) && !send;
  always @(posedge clk)
    if (nbits == 4'd0) begin
      // Wait one bit time before the start bit: that is what gives the previous
      // stop bit its full length when bytes follow back to back.
      if (send) begin sh <= {1'b1, data, 1'b0}; nbits <= 4'd10; baud <= DIV - 1; end
    end else if (baud == 16'd0) begin
      tx <= sh[0]; sh <= {1'b1, sh[9:1]}; nbits <= nbits - 4'd1; baud <= DIV - 1;
    end else
      baud <= baud - 16'd1;
endmodule
`default_nettype wire
