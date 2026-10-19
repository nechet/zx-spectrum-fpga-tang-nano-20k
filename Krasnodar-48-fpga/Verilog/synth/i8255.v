// -----------------------------------------------------------------------------
// FPGA build of the 8255 -- lib/i8255.v with its writes made synchronous to
// clk_sys (see the note at the write logic).  Reads are combinational, as
// before.
// -----------------------------------------------------------------------------
// Intel 8255A programmable peripheral interface (КР580ВВ55).
// Mode 0 only, which is all this board uses.  Ports are named after the DIP pin.
//
//   1..4   = PA3..PA0     37..40 = PA7..PA4
//   5=/RD  6=/CS  8=A1  9=A0  35=RESET  36=/WR
//   18..25 = PB0..PB7
//   10..13 = PC7..PC4     14..17 = PC0..PC3
//   27..34 = D7..D0
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module i8255 (
    inout  p1, p2, p3, p4, p37, p38, p39, p40,          // port A
    inout  p18, p19, p20, p21, p22, p23, p24, p25,      // port B
    inout  p10, p11, p12, p13, p14, p15, p16, p17,      // port C
    inout  p27, p28, p29, p30, p31, p32, p33, p34,      // data bus
    input  p5, p36, p6, p8, p9, p35,                    // /RD /WR /CS A1 A0 RESET
    input  p7, p26,
    input  clk_sys);             // wired up automatically by bus_resolve.py

  wire [1:0] sel = {p8, p9};
  wire [7:0] din = {p27, p28, p29, p30, p31, p32, p33, p34};

  reg [7:0] pa = 8'h00, pb = 8'h00, pc = 8'h00;
  reg [7:0] ctrl = 8'h9B;        // reset default: all ports input, mode 0

  wire a_out = ~ctrl[4];
  wire b_out = ~ctrl[1];
  wire cl_out = ~ctrl[0];        // PC3..PC0
  wire ch_out = ~ctrl[3];        // PC7..PC4

  wire [7:0] pa_pins = {p37, p38, p39, p40, p1, p2, p3, p4};   // PA7..PA0
  wire [7:0] pb_pins = {p25, p24, p23, p22, p21, p20, p19, p18};
  wire [7:0] pc_pins = {p10, p11, p12, p13, p17, p16, p15, p14};

  // ------------------------------------------------------------------ writes
  // The 8255 latches on the rising (trailing) edge of /WR, the instant the
  // CPU lets go of the data bus and address -- the same race as the border
  // latch.  So, like synth/sync_overrides.v's '298: while /WR is low, track
  // data, port select and /CS on clk_sys; on the rising edge, commit the last
  // values seen.  RESET is applied on clk_sys too.
  reg       wr_d = 1'b1;
  reg [7:0] din_r = 8'h00;
  reg [1:0] sel_r = 2'd0;
  reg       cs_r  = 1'b1;
  always @(posedge clk_sys) begin
    wr_d <= p36;
    if (!p36) begin
      din_r <= din; sel_r <= sel; cs_r <= p6;
    end
    if (p35) begin
      ctrl <= 8'h9B;
      pa <= 8'h00; pb <= 8'h00; pc <= 8'h00;
    end else if (!wr_d && p36 && !cs_r) begin
      case (sel_r)
        2'd0: pa <= din_r;
        2'd1: pb <= din_r;
        2'd2: pc <= din_r;
        2'd3: if (din_r[7]) begin                 // mode set
                ctrl <= din_r;
                pa <= 8'h00; pb <= 8'h00; pc <= 8'h00;
              end else begin                      // bit set/reset on port C
                pc[din_r[3:1]] <= din_r[0];
              end
      endcase
    end
  end

  // ------------------------------------------------------------------- reads
  reg [7:0] dout;
  always @(*)
    case (sel)
      2'd0: dout = a_out ? pa : pa_pins;
      2'd1: dout = b_out ? pb : pb_pins;
      2'd2: dout = {ch_out ? pc[7:4] : pc_pins[7:4],
                    cl_out ? pc[3:0] : pc_pins[3:0]};
      2'd3: dout = ctrl;
    endcase

  wire rd = ~p5 & ~p6;
  assign {p27, p28, p29, p30, p31, p32, p33, p34} = rd ? dout : 8'bz;

  // ------------------------------------------------------------- port drivers
  assign {p37, p38, p39, p40, p1, p2, p3, p4} = a_out ? pa : 8'bz;
  assign {p25, p24, p23, p22, p21, p20, p19, p18} = b_out ? pb : 8'bz;
  assign {p10, p11, p12, p13} = ch_out ? pc[7:4] : 4'bz;
  assign {p17, p16, p15, p14} = cl_out ? pc[3:0] : 4'bz;
endmodule
