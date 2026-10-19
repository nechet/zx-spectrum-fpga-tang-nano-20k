# core: the Krasnodar-48 board as FPGA logic

The board netlist, generated from the Krasnodar-48's EasyEDA schematic by
`../Krasnodar-48-fpga`, with the memory chips replaced by FPGA block RAM,
plus the top level that clocks it and puts it on HDMI. The Tang Nano 20K
builds in `../tang20k` use these files.

| | |
|---|---|
| `top.v` | the top level: clocks, reset, the board, the keyboard and SD bridge hook-ups, video (scan doubler, or `../tang20k/scan_tripler.v` with `HDMI_720P`), HDMI output, LEDs |
| `gen/` | **generated**: the board netlist with its shared data bus rewritten as explicit logic, and the part models it needs. Do not edit; `make` regenerates it |
| `fpga_memory.v` | the memory chips as block RAM: the 27C128 ROM (or the 32K two-bank ROM), the 16K x 1 video DRAMs, and with `RAM48` the upper 32 KB |
| `scan_doubler.v` | 576p video: each 896-clock board line shown twice at 27 MHz, locked to the board's frame |
| `hdmi_out.v`, `third_party/apicula/` | TMDS encoding, 10:1 serialisers and LVDS outputs (video only; with sound, `../tang20k/hdmi_audio_out.sv` takes its place) |
| `pll_135.v` | 27 -> 135 MHz for the 576p builds |
| `pll_sim.v` | simulation stand-ins for the Gowin PLLs, serialisers and LVDS buffers |
| `Makefile` | regenerates `gen/` |

## The board in the FPGA

Every chip of the schematic is a Verilog module (`../Krasnodar-48-fpga/Verilog/lib`,
synthesisable versions in `.../synth`), wired exactly as on the board. Three
things make that work on an FPGA:

* **One clock.** All the board's flip-flops run on `clk_sys` (135 MHz) and
  act on edges of the board's own 13.5 MHz clock, which they see as data
  (a clock enable). A chip's clock pin becomes an edge detector, not a
  clock net, so the tools can time everything.
* **The data bus.** On the board, five chips can drive D0..D7 through
  tri-state outputs. An FPGA has no internal tri-states, so
  `../Krasnodar-48-fpga/Tools/bus_resolve.py` rewrites the bus into
  explicit multiplexers, driven by each chip's enable.
* **The DRAM timing.** The board makes /CAS and the address multiplexer's
  switch-over from /RAS through RC delay lines (about 8 and 20 ns). They are
  counted out in 135 MHz clocks.

The CPU is the TV80 core (`../Krasnodar-48-fpga/Verilog/third_party/tv80`)
in the Z80's socket, stepping on the board clock's edges.

The visible window, measured in simulation: the picture starts 159 board
clocks into the line and 20 lines into the frame, and is 704 x 288 board
clocks: 352 x 288 Spectrum pixels. The paper starts 64 pixels into that
window, so its border is 64 pixels on the left and 32 on the right.

## Regenerating gen/

```sh
make
```

Needed only after a change to the schematic conversion or the part models
in `../Krasnodar-48-fpga`. The testbench scripts run it too; it does
nothing while `gen/` is up to date.
