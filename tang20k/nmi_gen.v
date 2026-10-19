// -----------------------------------------------------------------------------
// The loader key: F12 on the keyboard, or button S2, pulls the Z80's /NMI low
// once -- the Multiface's red button.
//
// The Z80 takes NMI on a falling edge, so one press must give exactly one
// clean pulse: the button is synchronised and debounced (it must read the
// same for 10 ms), F12 is already clean (a held-key level from the keymap),
// and after a pulse both are ignored until released, then for another 0.25 s.
// The pulse is 20 us long, far more than the Z80 needs (it samples /NMI at
// the end of every instruction).
// -----------------------------------------------------------------------------
`default_nettype none

module nmi_gen #(
    parameter integer CLK_HZ = 135_000_000
) (
    input  wire clk,
    input  wire f12,            // F12 held (clk domain)
    input  wire btn,            // button, active high, from the pin
    output wire nmi_n
);
  localparam integer DEB   = CLK_HZ / 100;        // 10 ms
  localparam integer PULSE = CLK_HZ / 50_000;     // 20 us
  localparam integer GUARD = CLK_HZ / 4;          // 0.25 s

  // --- button: synchronise, then debounce ---------------------------------
  reg [1:0]  bs = 2'b00;
  reg        bstable = 1'b0;
  reg [20:0] bcnt = 21'd0;
  always @(posedge clk) begin
    bs <= {bs[0], btn};
    if (bs[1] == bstable) bcnt <= 21'd0;
    else if (bcnt == DEB - 1) begin bstable <= bs[1]; bcnt <= 21'd0; end
    else bcnt <= bcnt + 21'd1;
  end

  // --- one pulse per press --------------------------------------------------
  wire       pressed = bstable | f12;
  reg  [25:0] t = 26'd0;           // pulse, then guard time
  reg        armed = 1'b1;
  always @(posedge clk) begin
    if (t != 26'd0) t <= t - 26'd1;
    if (!pressed && t == 26'd0) armed <= 1'b1;
    else if (pressed && armed && t == 26'd0) begin armed <= 1'b0; t <= GUARD + PULSE; end
  end
  assign nmi_n = !(t > GUARD);
endmodule
`default_nettype wire
