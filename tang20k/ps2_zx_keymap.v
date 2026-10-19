// -----------------------------------------------------------------------------
// PS/2 scancodes -> ZX Spectrum keys: the translation layer.
//
// Input: the byte stream from ps2_rx (scancode set 2).  E0 marks an extended
// key, F0 a release.  Output: `down`, one bit per Spectrum key, in the
// matrix order zx_matrix expects (key[row*5 + bit]).  All of the keyboard
// layout lives here; a USB keyboard front end would replace this module and
// ps2_rx, and keep zx_matrix.
// -----------------------------------------------------------------------------
`default_nettype none

module ps2_zx_keymap (
    input  wire        clk,
    input  wire [7:0]  code,
    input  wire        valid,
    output wire [39:0] down,       // 1 = key held
    output reg         f12 = 1'b0  // F12 held (the SD loader's menu key)
);
  // The Spectrum matrix, key[row*5 + bit]:
  //   row 0  A8   CAPS  Z  X  C  V        row 4  A12   0  9  8  7  6
  //   row 1  A9   A     S  D  F  G        row 5  A13   P  O  I  U  Y
  //   row 2  A10  Q     W  E  R  T        row 6  A14   ENTER L K J H
  //   row 3  A11  1     2  3  4  5        row 7  A15   SPACE SYM M N B
  reg [39:0] key = 40'd0;
  // PC keys that are a Spectrum key *combination*, kept apart so releasing
  // one does not release the other half of the combination.
  reg bksp = 1'b0, k_left = 1'b0, k_right = 1'b0, k_up = 1'b0, k_down = 1'b0,
      k_esc = 1'b0;
  reg ext = 1'b0, brk = 1'b0;       // E0 and F0 prefixes seen

  localparam CAPS = 0,  K_Z = 1,  K_X = 2,  K_C = 3,  K_V = 4,
             K_A = 5,  K_S = 6,  K_D = 7,  K_F = 8,  K_G = 9,
             K_Q = 10, K_W = 11, K_E = 12, K_R = 13, K_T = 14,
             K_1 = 15, K_2 = 16, K_3 = 17, K_4 = 18, K_5 = 19,
             K_0 = 20, K_9 = 21, K_8 = 22, K_7 = 23, K_6 = 24,
             K_P = 25, K_O = 26, K_I = 27, K_U = 28, K_Y = 29,
             ENTER = 30, K_L = 31, K_K = 32, K_J = 33, K_H = 34,
             SPACE = 35, SYM = 36, K_M = 37, K_N = 38, K_B = 39;

  always @(posedge clk) if (valid) begin
    if (code == 8'hE0)      ext <= 1'b1;
    else if (code == 8'hF0) brk <= 1'b1;
    else begin
      ext <= 1'b0;
      brk <= 1'b0;
      if (!ext) case (code)
        8'h12, 8'h59: key[CAPS]  <= ~brk;   // left / right Shift
        8'h14, 8'h11: key[SYM]   <= ~brk;   // left Ctrl, left Alt
        8'h1A: key[K_Z] <= ~brk;   8'h22: key[K_X] <= ~brk;
        8'h21: key[K_C] <= ~brk;   8'h2A: key[K_V] <= ~brk;
        8'h1C: key[K_A] <= ~brk;   8'h1B: key[K_S] <= ~brk;
        8'h23: key[K_D] <= ~brk;   8'h2B: key[K_F] <= ~brk;
        8'h34: key[K_G] <= ~brk;
        8'h15: key[K_Q] <= ~brk;   8'h1D: key[K_W] <= ~brk;
        8'h24: key[K_E] <= ~brk;   8'h2D: key[K_R] <= ~brk;
        8'h2C: key[K_T] <= ~brk;
        8'h16: key[K_1] <= ~brk;   8'h1E: key[K_2] <= ~brk;
        8'h26: key[K_3] <= ~brk;   8'h25: key[K_4] <= ~brk;
        8'h2E: key[K_5] <= ~brk;
        8'h45: key[K_0] <= ~brk;   8'h46: key[K_9] <= ~brk;
        8'h3E: key[K_8] <= ~brk;   8'h3D: key[K_7] <= ~brk;
        8'h36: key[K_6] <= ~brk;
        8'h4D: key[K_P] <= ~brk;   8'h44: key[K_O] <= ~brk;
        8'h43: key[K_I] <= ~brk;   8'h3C: key[K_U] <= ~brk;
        8'h35: key[K_Y] <= ~brk;
        8'h5A: key[ENTER] <= ~brk; 8'h4B: key[K_L] <= ~brk;
        8'h42: key[K_K] <= ~brk;   8'h3B: key[K_J] <= ~brk;
        8'h33: key[K_H] <= ~brk;
        8'h29: key[SPACE] <= ~brk; 8'h3A: key[K_M] <= ~brk;
        8'h31: key[K_N] <= ~brk;   8'h32: key[K_B] <= ~brk;
        8'h66: bksp  <= ~brk;      // Backspace = CAPS + 0 (DELETE)
        8'h76: k_esc <= ~brk;      // Esc       = CAPS + SPACE (BREAK)
        8'h07: f12   <= ~brk;      // F12: not a Spectrum key -- the loader menu
        default: ;
      endcase else case (code)
        8'h14, 8'h11: key[SYM] <= ~brk;     // right Ctrl, right Alt
        8'h5A: key[ENTER] <= ~brk;          // keypad Enter
        8'h6B: k_left  <= ~brk;             // cursor keys = CAPS + 5..8
        8'h72: k_down  <= ~brk;
        8'h75: k_up    <= ~brk;
        8'h74: k_right <= ~brk;
        default: ;
      endcase
    end
  end

  wire combo_caps = bksp | k_esc | k_left | k_right | k_up | k_down;
  assign down = key
      | (combo_caps ? (40'd1 << CAPS) : 40'd0)
      | (bksp    ? (40'd1 << K_0)   : 40'd0)
      | (k_esc   ? (40'd1 << SPACE) : 40'd0)
      | (k_left  ? (40'd1 << K_5)   : 40'd0)
      | (k_down  ? (40'd1 << K_6)   : 40'd0)
      | (k_up    ? (40'd1 << K_7)   : 40'd0)
      | (k_right ? (40'd1 << K_8)   : 40'd0);

endmodule
`default_nettype wire
