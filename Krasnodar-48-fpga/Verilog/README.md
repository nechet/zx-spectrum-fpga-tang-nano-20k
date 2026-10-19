# Krasnodar-48 — Verilog

A structural Verilog transcription of the board: every IC on the schematic is
one module instance, wired from the same netlist that drives the KiCad
conversion. The Z80 is a real soft core; the RAM and ROM are separate chips,
as they are on the board.

```
make run          # build with Icarus Verilog and run the smoke test
make wave         # same, plus tb_krasnodar48.vcd
make krasnodar48.v   # regenerate the netlist from the EasyEDA source
```

## Layout

| | |
|---|---|
| `krasnodar48.v` | generated top level — 65 chip instances, 235 internal nets |
| `lib/ttl.v` | 74LS/74ALS models (74LS00 … 74LS298) |
| `lib/cmos4000.v` | CD4000B models (CD4001 … CD4520) |
| `lib/i8255.v` | Intel 8255A PPI, mode 0 |
| `lib/memory.v` | 4164 / 16K×1 DRAM and the 27C128 EPROM |
| `lib/z80_chip.v` | 40-pin DIP wrapper around the TV80 core |
| `lib/analog.v` | stand-ins for the RC chains, the /INT differentiator and the crystal |
| `third_party/tv80/` | [TV80](https://github.com/hutch31/tv80) by Guy Hutchison, MIT licence |
| `tb/` | smoke-test bench and a small ROM image |

**Every chip port is named after its DIP pin** (`p1` … `p40`). That makes the
generated netlist a direct transcription of the schematic with no pin-name
mapping in between, and it is why `ttl_7400 D6 (.p1(A), .p2(B), .p3(Y) …)`
reads the way it does. `Tools/part-equivalents.md` says which Soviet part each
model stands in for.

## Top-level ports

| Port | |
|---|---|
| `clk14` | 14 MHz master clock (replaces the ZQ1 oscillator) |
| `res_n`, `nmi_n`, `wait_n`, `busrq_n` | CPU control inputs, pulled up on the board |
| `KD1…KD5` | keyboard column returns, pulled up |
| `jp_ru6` | J2, the КР565РУ6 / РУ5 RAM-type jumper |
| `vid_red`, `vid_green`, `vid_blue`, `vid_bright`, `vid_sync_n` | video, before the resistor DAC |
| `tape_in`, `tape_out`, `sound` | tape and beeper, at the digital side of the analogue conditioning |
| `PA0…PA7`, `PB0…PB7`, `PC0…PC7` | 8255 ports, brought out on X3 |

## What a netlist cannot carry across

The schematic is not purely digital, and the conversion says so rather than
pretending otherwise. Each item below is a deliberate substitution; the
generator prints the full list of dropped parts every time it runs.

* **The 14 MHz oscillator.** ZQ1 with R6/R7 around two D8 inverters is a ring
  oscillator, which has no meaning in a zero-delay digital simulation. The ring
  is cut at D8 pin 4 and `F14M` is driven from the `clk14` input instead.
* **The /INT differentiator.** C′ (750 pF) + R′ (22k) + VD1 turn the falling
  edge of the frame strobe `-KSI` into a low pulse on /INT. Replaced by
  `int_pulse`, which asserts /INT for R′C′ ≈ 16.5 µs.
* **The RC timing-correction chains.** Six series resistors with a shunt
  capacitor (R8–R12, R21, R47 — the «корректирующие RC цепочки» the project
  README mentions) become `rc_delay` instances with a transport delay of
  0.7·R·C. This preserves the intent, not the edge shape: the real network
  also slews the edge, which would matter if the receiving gate had
  hysteresis. None of them do.
* **The video DAC.** R35–R37 (620 Ω), R39–R41 (510 Ω), R43–R46 and VD7–VD9 sum
  R, G, B, BRIGHT and /SYNC into one analogue node. The digital signals are
  brought out instead; the summing network is not modelled.
* **Tape and sound conditioning.** R29–R34, R38, R42, C9–C14, C16, VD2/VD3 and
  the КТ361 output transistor are analogue. `tape_in`, `tape_out` and `sound`
  are the logic-level nets on the inside of that circuitry.
* **Decoupling capacitors** are dropped, as they carry no signal.
* **Unused gate inputs** are tied to `1'b1`, which is how a floating TTL input
  actually reads. There are four of them (D51/D52 serial inputs, two D62
  inputs); the generator lists them.
* **Timing.** All models are zero-delay. The board relies on real propagation
  delays in a few places, so cycle-accurate behaviour is not expected from
  this netlist without annotating the models with delays.

## Verification status

* The netlist the generator consumes is the one verified against KiCad — 256
  multi-pin nets, identical (reference, pin) membership.
* Every one of the 72 instances was checked mechanically against its module
  declaration: all ports connected, none invented, no undeclared identifiers.
* Chip pinouts (Z80, 8255, 27C128, the DRAMs) were checked against the pin
  names carried in the EasyEDA source.
* `make run` elaborates and simulates the whole board. With `tb/rom_test.hex`
  the Z80 fetches and executes the test program straight out of the modelled
  27C128, writes to video RAM and reads it back:

  ```
     2.25 us  M1 fetch  addr=0000  data=31     LD SP,$7FFF
     5.11 us  M1 fetch  addr=0003  data=3e     LD A,$AA
     7.11 us  M1 fetch  addr=0005  data=d3     OUT ($FE),A
    10.25 us  M1 fetch  addr=0007  data=32     LD ($4000),A
    13.96 us  M1 fetch  addr=000a  data=3a     LD A,($4000)
    17.68 us  M1 fetch  addr=000d  data=18     JR $
  ```

  So the ROM decode, the data bus, the DRAM row/column timing and the CPU core
  all work together as wired.

One model was corrected by this: the 74LS155's two halves are mirrored in the
package, `1Y0..1Y3` on pins 7,6,5,4 but `2Y0..2Y3` on pins 9,10,11,12.
With both running the same way, D11 decoded ROM to $4000 and the CPU fetched
nothing but zeroes; with the mirrored order the memory map comes out as a
Spectrum's — ROM at $0000, video RAM at $4000.

The chip models are written from datasheet behaviour and are not
silicon-accurate; the 74LS295 and 74LS298 clock on the falling edge, the
CD4520 counts on either a rising clock or a falling enable, and so on. Treat
this as a faithful transcription of the *wiring*, with device behaviour that is
correct in function but not in timing.

## ROM images

`rom_27c128` reads a `$readmemh` file — one hex byte per line:

```
make run ROM=path/to/48k.hex
```

`tb/rom_test.hex` is a six-instruction smoke test. A real Spectrum ROM needs
converting from binary to hex first; the board fits a single 27C128 in place of
the two РФ4 EPROMs of the original.
