// -----------------------------------------------------------------------------
// ZX Spectrum keyboard matrix: the machine side.
//
// The CPU reads the keyboard with IN (FE): A8..A15 carry a row mask, a 0
// selecting a row, and D0..D4 -- KD1..KD5 on the Krasnodar -- come back with
// a 0 for every pressed key in any selected row.  On the real keyboard that
// is done by diodes from the row lines to the key contacts; here it is an
// AND-OR over `down`.  Combinational: the answer is ready as soon as the
// address is, as with the real diodes.
//
//   row 0  A8   CAPS  Z  X  C  V        row 4  A12   0  9  8  7  6
//   row 1  A9   A     S  D  F  G        row 5  A13   P  O  I  U  Y
//   row 2  A10  Q     W  E  R  T        row 6  A14   ENTER L K J H
//   row 3  A11  1     2  3  4  5        row 7  A15   SPACE SYM M N B
//
// down[row*5 + bit].  Independent of where the key presses come from.
// -----------------------------------------------------------------------------
`default_nettype none

module zx_matrix (
    input  wire [39:0] down,       // 1 = key held
    input  wire [7:0]  a_hi,       // A15..A8: 0 selects a row
    output wire [4:0]  kd          // KD5..KD1 = D4..D0: 0 = pressed
);
  genvar c;
  generate
    for (c = 0; c < 5; c = c + 1) begin : col
      assign kd[c] = ~|{ ~a_hi[0] & down[0*5+c], ~a_hi[1] & down[1*5+c],
                         ~a_hi[2] & down[2*5+c], ~a_hi[3] & down[3*5+c],
                         ~a_hi[4] & down[4*5+c], ~a_hi[5] & down[5*5+c],
                         ~a_hi[6] & down[6*5+c], ~a_hi[7] & down[7*5+c] };
    end
  endgenerate
endmodule
`default_nettype wire
