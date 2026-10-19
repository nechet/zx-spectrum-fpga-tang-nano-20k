// -----------------------------------------------------------------------------
// PS/2 keyboard for the Krasnodar-48: three stages wired together.
//
//   PS/2 pins -> ps2_rx -> ps2_zx_keymap -> zx_matrix -> KD1..KD5
//                (bytes)   (40 keys down)    (answers the CPU's row select)
//
// Each stage is its own file and can be tested alone; see tb_kbd.v.
// -----------------------------------------------------------------------------
`default_nettype none

module ps2_keyboard (
    input  wire       clk,          // clk_sys
    input  wire       ps2_clk,      // from the pins, asynchronous
    input  wire       ps2_data,
    input  wire [7:0] a_hi,         // A15..A8 from the CPU: 0 selects a row
    output wire [4:0] kd,           // KD5..KD1 = D4..D0, 0 = pressed
    output wire       key_f12,      // F12 held: opens the SD loader menu
    // Test points for the LED probe build (PS2_LEDS); unused otherwise.
    output wire       dbg_clk_low,  // CLK line low now
    output wire       dbg_data_low, // DATA line low now
    output wire       dbg_clk_fall, // a CLK falling edge (pulse)
    output wire       dbg_valid,    // a good byte (pulse)
    output wire       dbg_err,      // a rejected frame: parity or stop bit (pulse)
    output wire       dbg_any_down, // at least one Spectrum key held
    output wire [7:0] dbg_code,     // the last byte received
    output wire [39:0] dbg_down     // the 40 Spectrum keys held
);
  wire [7:0]  code;
  wire        valid;
  wire [39:0] down;

  ps2_rx        rx     (.clk(clk), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
                        .code(code), .valid(valid), .err(dbg_err),
                        .clk_low(dbg_clk_low), .data_low(dbg_data_low),
                        .clk_fall(dbg_clk_fall));
  ps2_zx_keymap keymap (.clk(clk), .code(code), .valid(valid), .down(down), .f12(key_f12));
  zx_matrix     matrix (.down(down), .a_hi(a_hi), .kd(kd));

  assign dbg_valid    = valid;
  assign dbg_any_down = |down;
  assign dbg_code     = code;
  assign dbg_down     = down;
endmodule
`default_nettype wire
