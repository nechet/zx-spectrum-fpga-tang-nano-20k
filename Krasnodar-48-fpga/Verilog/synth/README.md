# FPGA resource estimate

Measured with yosys 0.52 targeting the Tang Nano 20K's GW2A family. Run
`make all` here to reproduce.

## Results

| Block | GW2A LUT / ALU / FF |
|---|---|
| TV80 Z80 core | 3 220 / 112 / 240 |
| Board glue — all 65 chips | 114 / 21 / 58 |
| **Total** | **3 334 / 133 / 298** |

## Against the Tang Nano 20K

| | Tang Nano 20K (GW2AR-18) |
|---|---|
| LUT4 available | 20 736 |
| Flip-flops available | 15 552 |
| Block RAM | 828 Kbit |
| **Logic used** | ~3 470 LUT → **17 %** |
| **Registers used** | 298 → **2 %** |
| **64 KB of ROM + RAM** | 512 Kbit → **fits**, 62 % of BSRAM |

The Z80 is ~96 % of the logic. The entire rest of the board — 49 gate
packages, 13 MSI parts and the 8255 — is 135 LUT slots, under 1 % of the
device.

Two details behind the numbers:

* TV80's register file is inferred as distributed LUT-RAM (12 × `RAM16SDP4`),
  which is why its flip-flop count is 240 here but 368 under a generic LUT4
  mapping. Expect 2 100–3 100 LUTs depending on the tool; Gowin's own EDA
  usually does better than yosys.
* The data-bus multiplexer is **not** in these figures. With the memories
  black-boxed, yosys sees several drivers on `D0…D7` and resolves them by
  keeping one. `Tools/bus_resolve.py` rewrites the bus into explicit logic —
  see `../../core/`, where the full design comes out at 3 095
  LUT4, within 1 of the estimate below.

## Memory is the binding constraint, not logic

| | |
|---|---|
| ROM (27C128) | 16 KB |
| Video RAM (8 × 16K×1) | 16 KB |
| Upper RAM (8 × 64K×1, 32 KB addressed) | 32 KB |
| **Total** | **64 KB = 512 Kbit** |

The **Tang Nano 20K** has 828 Kbit of BSRAM, so the whole 64 KB sits on-chip
with room to spare — and it also carries 64 Mbit of SDRAM if you want it.

## What had to change to make it synthesizable

`krasnodar48_synth.v` is the generator's `--synth` output. It differs from the
simulation netlist in three ways, all of them things a structural transcription
of a TTL board cannot avoid:

* **Pull-up resistors are commented out.** Synthesis has no wired-OR; every
  pulled net here is either a top-level input, where the pull is a board-level
  detail, or is actively driven once the tri-states become multiplexers.
* **`rc_delay` → `rc_delay_sync`**, a straight wire. The RC chains exist to
  shift an edge against gate propagation delay; in an FPGA there is no delay to
  correct. If a design needs them back, use a shift register on a faster clock.
* **`int_pulse` → `int_pulse_sync`**, a counter-based one-shot on `clk14`
  (231 cycles ≈ 16.5 µs) instead of an RC differentiator.

`counters_sync.v` additionally replaces three chip models that are valid
Verilog but not synthesizable, because the real parts are clocked from more
than one edge: the '193 (separate up and down clocks), the CD4520 (rising clock
*or* falling enable) and the '74 (drives X when preset and clear collide). A
real FPGA port restructures all three onto the system clock.
