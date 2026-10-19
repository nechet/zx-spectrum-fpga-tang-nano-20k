// Unit test for the PS/2 keyboard: real PS/2 frames in, KD1..KD5 checked for
// chosen row selections.  Self-checking; prints PASS/FAIL per case.
//
//   iverilog -g2012 -o simkbd tb_kbd.v ps2_keyboard.v ps2_rx.v \
//            ps2_zx_keymap.v zx_matrix.v && vvp simkbd
`timescale 1ns / 1ps

module tb_kbd;
  reg clk = 1'b0;
  always #3.7037 clk = ~clk;              // 135 MHz, as clk_sys

  reg ps2_clk = 1'b1, ps2_data = 1'b1;    // idle high (pulled up)
  reg [7:0] a_hi = 8'hFF;
  wire [4:0] kd;
  ps2_keyboard dut (.clk(clk), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
                    .a_hi(a_hi), .kd(kd));

  integer fails = 0;

  // One PS/2 frame, as a keyboard sends it: 12.5 kHz clock (40 us half
  // periods), data changed while CLK is high, read on CLK falling.
  task send_byte(input [7:0] b, input bad_parity);
    integer i; reg [10:0] f;
    begin
      f = {1'b1, ~^b ^ bad_parity, b, 1'b0};   // stop, odd parity, data, start
      for (i = 0; i < 11; i = i + 1) begin
        ps2_data = f[i];
        #20_000 ps2_clk = 1'b0;
        #40_000 ps2_clk = 1'b1;
        #20_000;
      end
      #200_000;                           // gap between bytes
    end
  endtask

  task expect_kd(input [7:0] rows, input [4:0] want, input [8*40-1:0] what);
    begin
      a_hi = rows; #100;
      if (kd === want) $display("PASS  %0s: rows %02h -> KD %05b", what, rows, kd);
      else begin
        $display("FAIL  %0s: rows %02h -> KD %05b, want %05b", what, rows, kd, want);
        fails = fails + 1;
      end
    end
  endtask

  initial begin
    #10_000;
    expect_kd(8'h00, 5'b11111, "nothing pressed, all rows");

    send_byte(8'h1C, 0);                                  // A down
    expect_kd(8'hFD, 5'b11110, "A down: row A..G, bit 0");
    expect_kd(8'hFE, 5'b11111, "A down: other row clear");
    expect_kd(8'h00, 5'b11110, "A down: all rows");
    send_byte(8'hF0, 0); send_byte(8'h1C, 0);             // A up
    expect_kd(8'hFD, 5'b11111, "A released");

    send_byte(8'h66, 0);                                  // Backspace down
    expect_kd(8'hFE, 5'b11110, "Backspace: CAPS (row 0, bit 0)");
    expect_kd(8'hEF, 5'b11110, "Backspace: 0 (row 4, bit 0)");
    send_byte(8'hF0, 0); send_byte(8'h66, 0);
    expect_kd(8'h00, 5'b11111, "Backspace released");

    send_byte(8'hE0, 0); send_byte(8'h6B, 0);             // cursor left down
    expect_kd(8'hFE, 5'b11110, "Left: CAPS");
    expect_kd(8'hF7, 5'b01111, "Left: 5 (row 3, bit 4)");
    send_byte(8'hE0, 0); send_byte(8'hF0, 0); send_byte(8'h6B, 0);
    expect_kd(8'h00, 5'b11111, "Left released");

    send_byte(8'h12, 0); send_byte(8'h1A, 0);             // Shift + Z both held
    expect_kd(8'hFE, 5'b11100, "Shift+Z: CAPS and Z, same row");
    send_byte(8'hF0, 0); send_byte(8'h12, 0);             // release Shift only
    expect_kd(8'hFE, 5'b11101, "Shift released, Z still held");
    send_byte(8'hF0, 0); send_byte(8'h1A, 0);

    send_byte(8'h29, 1);                                  // Space, bad parity
    expect_kd(8'h7F, 5'b11111, "bad-parity frame ignored");
    send_byte(8'h29, 0);                                  // Space, good
    expect_kd(8'h7F, 5'b11110, "Space down (row 7, bit 0)");

    $display("");
    if (fails == 0) $display("ALL PASSED"); else $display("%0d FAILED", fails);
    $finish;
  end
endmodule
