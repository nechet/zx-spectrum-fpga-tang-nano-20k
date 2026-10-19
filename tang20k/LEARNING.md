# Learning FPGA design and debugging -- through the Krasnodar-48 port

Written for a reader who knows classic digital electronics (TTL/CMOS, timing
diagrams, schematics) and is new to FPGAs.  This file explains *what* was done to get the Krasnodar-48 schematic running
on the Tang Nano 20K, and *why*, so it can be used to learn FPGA work.  Every
example is a real bug from this project.  Diagrams are plain text so they show
in any editor or terminal.

Contents

1. An FPGA, for someone who knows TTL
2. The tool flow used here
3. How the old board fits into the FPGA
4. Simulation vs. hardware -- the two ways to look inside
5. The debugging ladder we climbed
6. The big lesson: real TTL timing does not survive on an FPGA
7. Case studies (each bug, its symptom, its cause, its fix)
8. Habits worth copying
9. Glossary

---------------------------------------------------------------------------

## 1. An FPGA, for someone who knows TTL

Think of an FPGA as a huge breadboard of identical small parts, pre-wired
through programmable switches.  The parts:

| FPGA part | TTL-era equivalent | on the GW2AR-18 (20K) |
|---|---|---|
| LUT4 | any 4-input gate network -- a 16x1 PROM used as logic | ~20 000 |
| flip-flop | one '74 / '374 bit, with clock enable, set/reset | ~15 000 |
| block RAM (BSRAM) | 2716-class SRAM, 18 Kbit each, dual-port, *synchronous* | 46 |
| PLL | crystal + frequency multiplier / divider | 2 |
| I/O cell | '244 / '245 buffer with programmable standard (3.3 V, LVDS ...) | 88 pins |
| routing | the wires -- but each switch adds delay you don't choose | |

The FPGA is "programmed" by loading a bitstream into configuration SRAM (gone
at power-off; on boot it reloads from a flash chip).

### What is genuinely different from TTL design

1. **You don't draw, you describe.**  The circuit is written in an HDL
   (Verilog here).  Two kinds of statement map to the two kinds of logic:

   ```verilog
   assign y = a & ~b;                 // combinational: gates, settles continuously
   always @(posedge clk) q <= d;      // sequential: a D flip-flop, '74-style
   ```
   A tool (synthesis) turns this into LUTs and flip-flops.  You never pick
   individual gates.

2. **Gate delay is no longer a design tool.**  In TTL you knew a '04 adds
   ~10 ns and designs relied on it (delay lines, "this arrives after that").
   On an FPGA the logic delay is ~0.5 ns, but routing delay is unknown until
   place & route, and changes with every build.  **Any circuit whose
   correctness depends on which of two signals arrives first will be random.**
   Most bugs in this project come from exactly that (section 6).

3. **Synchronous design is mandatory.**  The clean way: one fast clock to
   every flip-flop through dedicated low-skew clock nets, and every other
   signal treated as *data* sampled on that clock.  Then the tools can prove
   timing: "every path from a FF to the next FF settles within one period"
   (*static timing analysis*, STA).  No scope needed.  Clocks made in logic
   (like `/WR` or a counter output clocking a latch) defeat that analysis and
   pick up skew from ordinary routing.

4. **No async tricks.**  No one-shots ('121), RC delays, wired-OR, or open
   collector inside the chip.  Tri-state exists only at the pins; an internal
   shared bus must become a multiplexer (that is what `bus_resolve.py` does to
   the Krasnodar's data bus).

5. **RAM is synchronous.**  Block RAM gives data one clock *after* the
   address.  Async DRAM chips are therefore modelled: the model samples
   /RAS, /CAS and /WE on the fast clock and responds like a 4116 would.

6. **You can simulate everything before building.**  The same Verilog runs
   in a simulator, where every signal is visible -- like a logic analyser
   with infinite channels.  That replaces most bench debugging.

## 2. The tool flow used here

```
 EasyEDA schematic (Krasnodar-48/, kept untouched)
        |
        |  Tools/easyeda_to_verilog.py      every chip -> one Verilog instance
        v
 Verilog/krasnodar48_synth.v   ("netlist": U_D1 is the Z80, U_D37 a '253 ...)
        |
        |  Tools/bus_resolve.py             shared data bus -> explicit logic,
        |                                   wires clk_sys into synchronous parts
        v
 core/gen/*.v    (GENERATED -- never edit by hand, see 7.8)
        |
        +---------------------------+------------------------------+
        |  SIMULATION               |  SYNTHESIS (hardware)        |
        v                           v                              |
  iverilog + tb_*.v           Gowin IDE 1.9.11 (gw_sh build.tcl)   |
        |                     synthesis -> place & route           |
        v                           |                              |
  vvp sim  -> text log /            v                              |
  waveform, minutes per             bitstream  *.fs                |
  10 ms of machine time             |                              |
                                    |  openFPGALoader -b tangnano20k
                                    v
                              Tang Nano 20K  -> HDMI monitor, LEDs
```

* **Synthesis** turns Verilog into LUTs and flip-flops.
* **Place & route** decides which physical LUT does what and how they connect,
  then checks *timing*: can every signal get from one flip-flop to the next
  within one clock period?  (At 135 MHz that is 7.4 ns.)
* We first used the open-source tools (yosys + nextpnr / "apicula").  On the
  GW2A chip of the 20K they produced a bitstream that *loaded* but computed
  wrong results -- a tool bug (apicula #541).  Switching to the vendor tool,
  Gowin IDE, fixed it.  Lesson: when simulation is right and hardware is
  wildly wrong, suspect the tools too, and try a second toolchain.

Commands used (from `core/`):

| what                         | command                                  |
|------------------------------|------------------------------------------|
| regenerate `gen/`            | `make gen/krasnodar48_synth.v`           |
| simulate memory-check ROM    | `make write WROM=testrom2.hex`           |
| simulate real-ROM start-up   | `make rom`  (log in `sim_rom.log`)       |
| build for the 20K            | `gw_sh build.tcl` in `../tang20k/gowin/` |
| load into FPGA (temporary)   | `openFPGALoader -b tangnano20k file.fs`  |
| write to flash (permanent)   | `openFPGALoader -b tangnano20k -f file.fs` |

---------------------------------------------------------------------------

## 3. How the old board fits into the FPGA

```
                        Tang Nano 20K  (GW2AR-18 FPGA)
   27 MHz    +--------------------------------------------------------------+
   crystal ->| PLL --> clk_sys 135 MHz (fast "sampling" clock, everywhere)   |
             |    \--> 14 MHz board master clock (what the real crystal was) |
             |                                                              |
             |   +--------------------------------------------+             |
             |   |  kras: the Krasnodar-48 board, chip by chip|             |
             |   |  Z80 (TV80 core)   ROM (block RAM)         |             |
             |   |  16 x DRAM chips (block RAM models)        |             |
             |   |  ~60 TTL chips: counters, muxes, latches   |  video      |
             |   |  8255 keyboard port                        |--- RGB ---->|
             |   +--------------------------------------------+  15 kHz     |
             |                                                   |          |
             |   scan_doubler (line buffer, 15 kHz -> 31 kHz)  <-+          |
             |        |                                                     |
             |   hdmi_out (TMDS encoding, 10x serialiser) -----> HDMI pins  |
             |   LEDs: sticky error checkers on the raster                  |
             +--------------------------------------------------------------+
```

We did not rewrite the Spectrum as a "clean" design.  We **simulate the
original board chip by chip**, so the FPGA behaves like the real Krasnodar-48
including its quirks.  The price: every place where the real board relied on
the analog timing of TTL chips needs care (section 6).

---------------------------------------------------------------------------

## 4. Simulation vs. hardware -- the two ways to look inside

| | Simulation (iverilog) | Hardware (the 20K) |
|---|---|---|
| speed | ~10 ms of machine time per minute | real time |
| visibility | **every** signal, every nanosecond | only the monitor and 6 LEDs |
| faithfulness | only as good as the models | the truth |
| turnaround | compile 10 s | Gowin build ~5 min |

The working method is a loop:

```
   observe on hardware  --->  form a hypothesis  --->  reproduce in simulation
          ^                                                   |
          |                                                   v
   build + flash  <---  fix the model  <---  find the exact signal that is wrong
```

**Reproduce first, then fix.**  A fix you can't see working in simulation is
a guess.

A *testbench* (`tb_*.v`) is Verilog that is never synthesised: it makes the
clock, instantiates the design (`dut`), and prints things.  It can reach any
signal inside by its hierarchical name, e.g. `dut.kras.U_D61.q` is the border
latch.  Example from `tb_rom.v`:

```verilog
always @(negedge m1_n)                    // every Z80 opcode fetch
  if (a == 16'h11DC)                      // the ROM's RAM-FILL routine
    $display("[%0t] reached RAM-FILL, HL=%04h", $time, hl);
```

Instead of staring at waveforms, we print **only the events that answer the
question** ("which ROM routine did it reach?", "which cell did this write
land in?").  That keeps 100 ms of simulation readable.

---------------------------------------------------------------------------

## 5. The debugging ladder we climbed

Never debug the whole system at once.  Climb one rung at a time; each rung
proves a layer so the next failure has fewer suspects.

```
  rung  test                              proves                    result
  ----  --------------------------------  ------------------------  -------
   1    LED blink                         FPGA loads, clock runs    OK
   2    HDMI self-test (colour bars)      HDMI pins, PLL, encoder   OK
   3    board video, CPU in reset         sync timing, raster       OK (LED checkers)
   4    test ROM 1: OUT border + LDIR     CPU runs, writes, video   OK (stripes)
          fills screen with stripes       fetch, attributes
   5    test ROM 2: memory check          read-modify-write in RAM  OK (green)
          (DEC (HL) twice per byte)
   6    real Spectrum ROM                 everything                IN PROGRESS
```

Test ROMs are tiny Z80 programs (`testrom*.asm`) that **report through
something we can see**.  With no serial port, the border colour is our
"printf":

```
   blue  = started        red = failed        green = passed
```

When the real ROM hung, writing a 40-line test ROM that does *just* the step
it hung in (its memory check) turned a vague symptom into a yes/no question.

---------------------------------------------------------------------------

## 6. The big lesson: real TTL timing does not survive on an FPGA

On the real board, many chips are clocked by signals made by *other* chips
(`/WR`, `/RAS`, a counter output ...), and some capture data on the **same
edge** where that data changes.  It works in TTL because each gate adds
~10-20 ns of delay, and the designer knew which signal arrives first.

```
  real TTL:  /WR rises ... 15 ns later the data bus changes
             data  ===========X==========
             /WR   ______/‾‾‾‾‾‾‾          the latch catches the OLD data. OK.
                         ^ capture   ^ data changes (gate delay later)
```

On an FPGA the routing delays are tiny and arbitrary, so the order flips
from build to build:

```
  FPGA:      data  ======X===============
             /WR   ______/‾‾‾‾‾‾‾          data changed first: WRONG value
                         ^ capture
```

**The fix pattern used everywhere -- edge detection on the fast clock.**
Don't use `/WR` as a clock at all.  Sample it with `clk_sys` like any data,
remember last cycle's value, and act when "was 1, now 0":

```verilog
reg ck_d;
always @(posedge clk_sys) begin
  ck_d <= strobe;                       // strobe as it was one clock ago
  if (strobe) saved <= data;            // keep the data while strobe is high
  if (ck_d && !strobe) q <= saved;      // falling edge seen: commit what we saved
end
```

```
  clk_sys   _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_      (7.4 ns per tick)
  strobe    ‾‾‾‾‾‾‾‾‾‾‾‾‾\______________
  data      ====D=========X====junk=====
  saved     ----D----D----D--------------   (frozen once strobe is low)
  ck_d      ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________
  q         ------------------D---------    always the good value
```

Now there is only **one** clock, and the tools can check every path.  It
behaves the same in simulation and on hardware.  Parts converted this way:
74298 (border latch), 74175 (attribute latch), 74295 (pixel shifter), 74193,
7474, 4520 (counters), the DRAM models.  They live in
`Krasnodar-48-fpga/Verilog/synth/sync_overrides.v` and `counters_sync.v`.

---------------------------------------------------------------------------

## 7. Case studies

Each one: **symptom -> how we found it -> cause -> fix.**

### 7.1 Monitor shows "no signal" -- the toolchain bug
* Symptom: LEDs fine, HDMI colour bars fine, the board design: no sync.
* Found by: the same design simulated perfectly; small designs worked on
  hardware; only the big one failed.  The raster-checker LEDs showed the board
  timing itself was dead *inside* the FPGA.
* Cause: open-source GW2A flow miscompiles (apicula #541).
* Fix: build with Gowin IDE 1.9.11.
* Lesson: an early wrong theory ("the monitor rejects the mode") cost time.
  Add a check that *measures* the claim (the LED raster checkers) before
  believing it.

### 7.2 Blue border instead of white -- trailing-edge capture
* Symptom: ROM writes border 7 (white); screen showed 1 (blue).
* Found by: `make boot` -- in simulation the CPU did `OUT (FE),07` correctly.
  So CPU fine, latch wrong.
* Cause: the '298 latch captures on the *rising end* of `/WR`, exactly when
  the select (`/IORQ`) and data bus also change (section 6).
* Fix: synchronous '298, edge-detected on `clk_sys`.

### 7.3 Video read only 54 different addresses -- the DRAM address mux
How DRAM works: the address goes in **two halves on the same pins**.

```
  address pins  ==ROW====X====COLUMN=========
  /RAS          ‾‾‾‾\_______________________   falls: chip latches ROW
  /CAS          ‾‾‾‾‾‾‾‾‾‾‾‾‾\______________   falls: chip latches COLUMN
                    ^ row must still be       ^ column must be there
                      on the pins here
```

On this board the 74253 multiplexer switching row->column is driven **by /RAS
itself**.  It only works because the real '253 takes ~20 ns to switch -- the
row stays on the pins just long enough after /RAS falls.  A zero-delay model
switched instantly: the DRAM latched the *column as the row*.

* Fix: the '253 select takes effect one `clk_sys` late (models the real
  propagation delay), while its data inputs pass straight through.

```
  clk_sys   _|‾|_|‾|_|‾|_|‾|_|‾|_
  /RAS      ‾‾‾‾‾‾\_____________
  sel(raw)  ‾‾‾‾‾‾\_____________
  sel(used) ‾‾‾‾‾‾‾‾‾‾\_________     one clock later
  mux out   ==ROW=======X=COL===
  DRAM        latches ROW ^ here (sees /RAS fall)  -> correct
```

### 7.4 Black screen in simulation -- testbench bug, not design bug
* The testbench preloaded the screen at the *logical* address, but the board
  scrambles address bits on the way to the DRAM.  Fix: a `phys()` function in
  the testbench, verified by a round-trip check (logical -> physical ->
  logical must give back the same address).
* Lesson: when a test fails, the test is a suspect too.

### 7.5 Pixel shifter loaded 1111 -- output enable timing
* The DRAM model released its output when /RAS rose, but the board loads the
  pixel shifter on the edge that *ends* the read.  A real DRAM keeps data
  valid for a short "turn-off time" after /CAS.  Fix: output depends on /CAS
  only, plus a 3-clock hold.

### 7.6 Writes stored the previous byte -- CPU core configuration
* TV80 (the Z80 core) option `T2Write(1)` drops `/WR` earlier than a real
  Z80, before the data is on the bus.  The board's DRAM does "late write"
  and took the old bus value.  Fix: `T2Write(0)` -- real Z80 timing.
* Lesson: an IP core's options must match the *real* chip when you put it in
  an old circuit.

### 7.7 CPU never paused for video -- inverted enable in a library model
* The 74155 decoder model had enable 1 with the wrong polarity, so the
  "CPU wants screen memory" signal never fired and the CPU and video fought
  over the DRAM.  Found by dumping the arbitration signals in `tb_write.v`.
  Fix: `en1 = p1 & ~p2` in `lib/ttl.v`.
* Lesson: check library parts against the datasheet's function table.

### 7.8 The fix that undid four fixes -- generated files
* Symptom: after fixing 7.7, CPU writes landed in wrong cells again.
* Found by: probe printing the '253 select at the moment the DRAM latched the
  row: `sel=10` -- already the column.  Then: why is there no delay at all?
  `grep clk_sys gen/lib_sync.v` -> nothing.
* Cause: `synth/lib_sync.v` is **generated** from `lib/ttl.v` by
  `mk_synth_lib.py`.  Editing `ttl.v` made `make` regenerate it, silently
  throwing away the four hand-written synchronous models (7.2, 7.3, '175,
  '295) that had been typed into the generated file.
* Fix: the models now live in their own source file `sync_overrides.v`, which
  the generator merges in.
* Lesson: **never hand-edit a generated file.**  Look for "generated by"
  rules in the Makefile before editing anything.  Use version control (git) so
  `git diff` shows what changed.

```
  BEFORE                                   AFTER
  lib/ttl.v --gen--> lib_sync.v            lib/ttl.v ------+
                       ^ hand edits        sync_overrides.v +--gen--> lib_sync.v
                       (lost on regen)     (edits live here, safe)
```

### 7.9 Real ROM: black screen -- when simulation and hardware disagree
* The memory-check test ROM passes (green) in simulation **and** on hardware.
* The real ROM on hardware: white border, the fill visible as moving
  artifacts, then the check turns the screen black -- and it stays black.
* `tb_rom.v` (1.1 s of machine time, ~2 hours) says the design **boots fully
  in simulation**:

```
   38 ms  START, border white, RAM-FILL from FFFF down
  504 ms  RAM-READ: check 4000 upward (02 -> 01 -> 00, screen goes black)
  947 ms  RAM-DONE at 8000  (16K machine: upper 32K not fitted, as designed)
  950 ms  CLS               (paper should turn white here)
  951 ms  first IM1 interrupt -> KEYBOARD
 1007 ms  PO-MSG            (copyright printed on the bottom line)
 1022 ms  EDITOR -> WAIT-KEY, interrupts at 50 Hz
```

* So the logic is right, and something differs on the real chip right
  after the check.  When that happens you **move the probe to the hardware**.
  A testbench can name any signal (`dut.kras.U_D1.a`); synthesis cannot, so
  the debug build (`gowin_bootleds/`) uses a copy of the netlist with two
  extra output ports -- the address bus and /M1 -- and top.v latches LEDs
  on opcode fetches from the same ROM routines `tb_rom.v` watches:

```
   /M1 (board signal) --> 3-FF synchroniser on clk_x5 --> falling-edge detect
                                                            |
   A15..A0 ------------------------------------------> compare with 11EF, 0D6B,
                                                        0038, 0C0A, 15D4, 0000
                                                            |
                                                      sticky LED flip-flops
```

  The last LED that lights is where the hardware stops.  This is the
  FPGA-era equivalent of hanging a logic probe on a test point -- except
  you *add* the test point to the circuit and rebuild.  (Vendor tools also
  offer an embedded logic analyser -- Gowin's is "GAO" -- that records
  internal signals into block RAM and shows them over JTAG.  LEDs are
  simpler when the question is "how far did it get?".)

### 7.10 Boots, then crashes -- the clocks nobody declared
* LEDs from 7.9: RAM-DONE, CLS, PO-MSG, WAIT-KEY all lit -- then LED5,
  "restarted".  The ROM booted completely and then crashed, and each build
  crashed at a different point.  Different results from the *same logic* in
  different builds means **timing**, not logic.
* Gowin's timing report (`impl/pnr/*_tr_content.html`, "Clock Summary") listed
  a dozen clocks nobody had created: `kras/CLK`, `wr_n`, `N_55`, `V2`, `V3`,
  `V9`, `F3_5M` ...  Every `always @(posedge some_board_signal)` turns that
  signal into a clock net.  Paths *between* such clocks are not analysed at
  all, and the routing skew changes every build.
* Worst of all, the Z80 itself was clocked by the board's gated `CLK`, and
  `/INT` came from logic clocked by the same 14 MHz.  So `/INT` could change
  at the exact instant the CPU sampled it -- with the CPU's flip-flops then
  disagreeing about whether an interrupt had arrived.  A real Z80 has input
  latches; the model had none.
* Fix: **every** flip-flop on `clk_sys`.  The CPU core gets TV80's clock enable
  (`cen`), pulsed once per detected rising edge of `CLK`; its inputs are
  synchronised and held from one `CLK` fall to the next:

```
  CLK (board)  ‾‾‾‾\________/‾‾‾‾‾‾‾‾\________/‾‾‾
  clk_s2       ‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾\________/   two-FF synchroniser
  rise         _______________|‾|_______________|‾|  registered, one clk_sys wide
  fall         _______|‾|_______________|‾|_______
  /INT (held)  ======X=================X==========  changes only on `fall`
  CPU steps                   ^                 ^   always sees a steady /INT
```

* A first attempt used the *raw* `CLK` inside `rise` -- an asynchronous
  signal straight into the enable of ~1000 flip-flops.  Some stepped, some
  did not, and the CPU never reached its first instruction.  Simulation,
  having no routing delay, could not show it.  **An asynchronous signal must
  pass a synchroniser before it fans out.**
* Then a constraints file (`krasnodar.sdc`) told Gowin the CPU's internal
  paths have 8 clk_sys cycles, not one (`set_multicycle_path`), so it stops
  sacrificing real paths to impossible ones.

### 7.11 No HDMI sync -- a 7 ns glitch
* With the CPU fixed, the monitor lost sync.  Colour bars synced; the board's
  picture did not -- even with the bars' *exact* timing (896 x 624).  A mixed
  build (the bars' sync, the board's pixels) synced, which put the fault in
  the board-to-doubler path.
* Simulation: the board made **two** line syncs per line (30 kHz).  The sync
  is `hsync_n = NAND(~V3, N_125)`, where `N_125` is a CD4013 flip-flop that
  `V5` resets asynchronously.  `V3` and `V5` are bits of one counter and change
  on the same tick (count 7 -> 8):

```
  counter     ..6  |  7  |  8  ..
  ~V3         _____/‾‾‾‾‾‾‾‾‾‾‾‾      (V3 falls at 7->8)
  V5 (reset)  ___________/‾‾‾‾‾‾‾      (rises at 7->8)
  N_125 real  ‾‾‾‾‾‾‾‾‾‾‾\______      reset acts at once
  N_125 sync  ‾‾‾‾‾‾‾‾‾‾‾‾\_____      reset applied one clk_sys late
  hsync_n     ‾‾‾‾‾‾‾‾‾‾‾|_|‾‾‾‾      7 ns glitch = a second "line"
```

* The LED checkers missed it: they sample once per board pixel (74 ns).
* Fix: asynchronous set/reset/clear/load stay asynchronous -- applied to the
  *outputs* combinationally, and to the stored state on `clk_sys`.  Clock
  edges are synchronous; resets are gating.  That is what the chip does.
* Two more HDMI-side lessons from the same hunt:
  - the HDMI serialiser (`OSER10`) needs PCLK = FCLK / 5 **in phase**; derive
    the pixel clock from the fast clock with `CLKDIV`, don't take it from the
    crystal pin;
  - send the TMDS clock lane through a serialiser too, so all four lanes come
    out of identical hardware.

### 7.12 A white stripe -- the board needs slow CMOS
* The copyright screen appeared, with a bright-white, flickering column at
  the right edge of the paper.  Bright white = attribute FF = the idle bus:
  the 32nd character was never fetched.
* A fetch log (`tb_fetch.v`) showed two fetch slots per character-counter
  step.  Slot A sits on the same edge that advances the counter, so it fetches
  the *previous* odd character; character 31 therefore comes from slot A of
  the step *after* the last -- on the very edge where the CD4015 shift register
  closes the display window:

```
  char clock    _|‾‾‾‾‾‾‾‾‾‾‾‾|____...           (one step = 2 characters)
  slot A fetch   ^ x31 must happen here
  window real   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____    CMOS 4015: output ~300 ns after the edge
  window model  ‾\_________________    7 ns after the edge: fetch suppressed
```

* On the real board the 4000-series CMOS (250-400 ns at 5 V) is slow enough
  that the last fetch completes before the window closes, and the window
  opens only after a stray fetch at the start has passed.  The designer
  relied on it -- probably without thinking of it as a "feature".
* Fix: the CD4015 model's outputs go through a 40-tick (~300 ns) delay line.
  Result: all 32 characters fetched, line and frame timing unchanged.
* Lesson: an exact functional model can still be *wrong* if the board depends
  on a part being slow.  When a design behaves at the edges of a window,
  ask what the real propagation delays were.

### 7.14 Works after flashing, fails after reset -- making "sometimes" repeatable
* Symptom: copyright screen every time after loading the bitstream; after the
  reset button, usually garbage.  The LED build said the CPU booted and then
  crashed.
* **Turn the vague symptom into a counted one.**  `testrom3.asm` runs the
  ROM's memory check over 512 bytes in a few milliseconds and shows
  green/red.  On the board: green after flashing, mostly red after reset.
* **Reproduce it in simulation.**  `tb_phase.v` first released the reset at 8
  different phases -- all passed (the first screen access re-aligns the CPU
  to the video, so the start phase alone did not matter).  Then it pressed
  reset *while the machine ran* -- 8 of 8 failed.  Now it could be traced.
* Write log: after the reset, a CPU write landed in the *video's* DRAM row.
  The edge dump showed why -- two separate causes:

```
  1. the CPU core:  real Z80 write     /MREQ falls in T1, /WR in T2
                    tv80n (T2Write=0)  /MREQ and /WR both in T2  <- late
     The board's arbitration samples the CPU's look-ahead around T1; a late
     /MREQ could fall as the video window opened, and nothing held the CPU.
     Fixed in the wrapper (synth/z80_chip.v): /MREQ from T1 on writes.
     -> 7 of 8 reset phases pass.

  2. the window edge: the CD4015 delay (7.12) was 40 ticks = exactly two
     periods of N_55, the arbitration clock.  The window therefore always
     opened 5 ticks after an N_55 edge -- the same tick the CPU's /MREQ fell.
```

* The delay turned out to have three constraints at once: open *before* an
  N_55 edge (<= 34 ticks), open before the video sequencer samples it (53
  was too late -- the fetches slid into the CPU's slots), and close only
  after the 32nd character's pixel fetch (>= 40).  Opening and closing come
  from opposite output transitions, and real CMOS has different rise and fall
  delays, so the model got both: rising 40 ticks, falling 33 ticks
  (`out = delayed_40 & delayed_33`).  Result: 8 of 8 reset presses pass,
  column 31 complete, line and frame timing unchanged.
* Lessons:
  - "after flashing vs after reset" means *initial state or alignment* --
    find what reset does not restore;
  - a delay that is an exact multiple of another clock locks you into one
    phase forever: good or bad, but never sampled;
  - when one number has to satisfy several constraints, write them all
    down before choosing it (I tried 53, then 33, before doing that).

### 7.13 Two smaller lessons from the same day
* **Generated code and stricter tools.**  Icarus Verilog 14 rejected the
  netlist: `bus_resolve.py` declared its wires *after* using them.  Older
  tools tolerated it; the language does not allow it.  Fixed in the
  generator, not in the generated file (7.8).
* **Check your testbench's units.**  `$time > 45_000_000_000` with a 1 ns
  timescale is 45 *seconds*; the probe silently never fired.

### 7.15 PS/2 keyboard: "no reaction" -- splitting a chain of suspects
The keyboard path crosses two boards and five stages:

```
 USB kbd -> RP2040 (ps2pico) -> wires -> pin 73/74 -> ps2_rx -> keymap -> zx_matrix -> KD1..5 -> Z80
            LED blue/magenta            ground test   LED/UART   UART       UART (kd)    border/BASIC
```

"No reaction on keys" says only that *something* in that chain is broken.
What found it, in order:

* **Check the board schematic, not just the FPGA pinout.**  Pins 25/26 looked
  free; the schematic showed them also wired to the HDMI connector (HPD via
  2.2k, CEC via 100R).  Moved to 73/74, which go only to the header.  And
  "pin 73" means the *silkscreen label*, not the 73rd hole.
* **Inject a known signal at the input.**  Grounding a pulled-up input pin
  (safe -- never do it to an *output*) must light a probe LED.  When even
  grounding an LED pin itself did nothing -- pure physics: 3.3 V, LED,
  510R, ground -- the conclusion was certain: the wire never touched the
  hole.  A bad contact, not a design bug.
* **The tool can silently ignore you.**  Splitting the constraints into a
  board file and a pin-pair file, Gowin read *only the last* .cst file.  The
  next builds had LEDs, clock and HDMI on random pins -- and LED readings
  that made no sense.  The PnR report showed it: those ports were "not
  locked" and LVCMOS18.  Fix: concatenate into one `combined.cst`.  Lesson:
  after every build check the pin report for *all* ports.
* **Replace LEDs with a serial log.**  Six LEDs read out over a chat are
  ambiguous (which end is LED0?).  `ps2_uart_mon.v` prints every PS/2 byte,
  the 40-key state, the KD lines the CPU's scan reached, and the number of
  CLK edges per second, through the board's own USB serial port (pin 69 ->
  /dev/ttyUSB1).  A logic analyser built into the design.  "0 edges in 3
  minutes" pointed straight at the adapter connection; once fixed, the log
  showed `14 12` (Ctrl, Shift) -> keys 36 and 0 held -> `kd 1C`.
* **The last "bug" was the Spectrum.**  Holding CAPS+SYMBOL for 3 s never
  gave the E cursor: it is a toggle, and the ROM's auto-repeat flips it
  every few hundred ms.  A quick tap works.  Know the machine's own
  behaviour before blaming your hardware.
* Lessons:
  - an indicator that changes *before* the action (the RP2040's LED is set
    before it transmits) proves intent, not delivery;
  - split a chain at its middle with a known signal, as with a logic probe;
  - give the design a voice: a UART monitor costs a few hundred cells and
    replaces guessing.

### 7.16 48K: half a chip, a swapped guess, and a build that lied

Adding the upper 32 KB (D23-D30, eight КР565РУ5 64K x 1) to the 20K.

* **Read the board before sizing the memory.**  Eight full 64K x 1 parts
  would need 32 BSRAM blocks -- 49 of 46 with what is already used.  But the
  netlist shows the address multiplexer D22 putting a jumper (`jp_ru6`) on
  MA7 in one of the two strobe phases, and /CAS5 only falling when A15 = 1.
  One address bit is constant: each chip is really used as 32K x 1, two
  blocks, 16 in all.  The TTL-era reason: the Z80's refresh counter (the R
  register) only cycles through 128 rows, so on a 256-row DRAM half the rows
  are never refreshed -- the designer simply never uses them.  Sinclair did
  the same thing with cheap "half-good" 4532 chips.
* **Write the test before the fix, and run it against the old design
  first.**  `testrom5` fills two pages, walks every address bit (8000h plus
  2^k, all written before any is read back), and checks that video RAM at
  4000h does not alias C000h; the border goes green or red.  On the 16K
  model it went red -- proof the test can fail.
* **The test then caught my mistake.**  I had guessed the jumper rode on
  the *column* phase and stored row x 7 column bits.  Red again, later.  A
  reference memory in the testbench (record every CPU write, check every
  read) named the address: 8000h read 02, wrote 03.  Logging the chip's
  own row/column for each write showed C000h and 8000h landing on the same
  cell: the varying bits were A0..A6 on the *row* strobe and A7..A14 on the
  column strobe, so I had thrown away A14.  The address-bit walk exists for
  exactly this: a dropped or swapped line makes two walk addresses share a
  cell.  In logic-analyser terms: trigger on the first wrong read, then look
  one level down.
* **The build said success; it wasn't.**  The model clears its cells at
  power-up in a `for` loop -- now 32 768 iterations, over Gowin's loop
  limit of 20 000.  Gowin printed `ERROR (EX3934)`, made `dram_x1` an empty
  black box, *exited 0*, and left the old bitstream in place.  The tell was
  BSRAM still 17/46 where 33 were expected.  Fixed with `-looplimit 40000`,
  and `build.sh` now fails on any `ERROR` line or a `.fs` older than the
  build -- a tool's exit code is a claim, not a proof.
* On the board: `PRINT PEEK 23732+256*PEEK 23733` (P_RAMT, the top of RAM
  the ROM found at start-up) gave 65535.  The ROM's own memory test is a
  free second opinion.

### 7.17 SD card: passes every simulation, silent on the board -- timing

Step 2 of the SD loader (FAT32 listing, `fat32.v`) passed its testbench --
fragmented files, a three-cluster folder, long-name entries -- and on the
board printed nothing at all, not even its error message.  The step 1
bitstream still worked, so card and wiring were fine.

* **Simulation has no gate delays.**  An RTL simulator evaluates every
  expression in zero time; the hardware needs nanoseconds per gate.  The
  sector-number calculation `data_lba + (c - 2) << spc + s` -- three adders and
  a shifter in one clock -- needed 11.7 ns, and the clock was 7.4 ns (135 MHz).
  The flip-flops captured half-finished sums, the state machine asked the card
  for nonsense sectors, and waited for ever.  TTL equivalent: four '283s in a
  ripple chain between two '374s, clocked faster than the carry can settle.
* **Gowin said so -- quietly.**  The timing report: Fmax 85 MHz, 443 failing
  endpoints.  It still writes the bitstream.  `build.sh` now prints the Fmax
  and any negative slack after every build.
* **Two ways to fix it.**  Pipelining -- one operation per clock, a register
  after each (`S_L0..S_L3`) -- brought it to 134.8 MHz, then the next-longest
  paths appeared.  The better answer: the card does not need 135 MHz.  The SD
  side now runs on the board's own 27 MHz crystal clock (Fmax 81 MHz: three
  times the margin), like a 1980s disk controller with its own crystal.  The
  cost is a clock-domain crossing to the Z80 side, which needs synchronising
  anyway.
* A knock-on detail: at 27 MHz the SPI clock is 13.5 MHz, one system clock per
  half-period, so MISO must be sampled straight from the pin -- through an
  extra register it would be the *previous* bit.
* Result: all seven games listed, every checksum equal to the PC's.

### 7.18 SD menu: yellow screens, and colours that came from register A

Step 3 (the bridge on the 8255, NMI on F12 / S2, the menu in the ROM) passed
its simulation, and on the board the machine did not even boot: yellow
screen, no copyright.  Two unrelated faults were stacked on top of each other.

* **Bisect the build, not the guess.**  Known-good bitstream: boots.  New
  netlist without the SD logic: boots.  SD logic with the *original* ROM:
  yellow.  Then the same build plus six LED wires: boots.  Logic that works or
  fails depending on how it happens to be placed is timing (habit 13), not
  logic.
* **The DRAM chips trusted the first clock.**  Each modelled КР565РУ5 acted on
  the first 135 MHz tick after /RAS, /CAS or /WE fell.  Those strobes come
  through the board's gates -- the CD4015 delay line, decoders, the /CAS
  multiplexer -- about 11 ns of logic against a 7.4 ns tick.  So the chip
  could catch a half-settled strobe or address and write the wrong cell, or
  miss a write.  The full timing report (`report_timing -max_paths 300` in
  the .sdc) showed it once the Z80's own harmless paths stopped hiding it.
  The fix is the one a careful TTL designer uses for a noisy strobe: latch
  every pin once, believe a strobe only when two latches in a row agree, and
  take address and data from the older latch.  About 22 ns of extra access
  time, against the board's ~150 ns.  Total negative slack: -572 ns -> -104 ns.
* **The colours were whatever was in A.**  The menu still drew white-on-white
  rows and a black bar.  A disassembly showed it: z80asm read `ld b, A_BAR` as
  `ld b,a` -- a symbol starting with a register letter and `_` is taken as the
  register, with no warning.  Renamed to `COL_BAR` etc.  The simulation had
  passed because it only compared text pixels; it now checks the colour bytes
  too.  TTL equivalent: a net label the wire-wrap list misread as a pin name.

### 7.19 The .z80 loader: loading over your own feet

A snapshot fills all 48K of RAM -- including the stack, the menu's variables,
anything a loader would normally keep.  The only memory that survives is the
ROM, which is where the loader runs.  Three tricks, all old ones:

* **Borrow the game's stack.**  The header gives the game's SP.  The loader
  moves there before loading; its CALLs only ever touch the few bytes just
  under it, which in any program are free stack space.  Every byte loaded is
  written between calls, when nothing on the stack is live.
* **Keep nothing; read it again.**  The header is not saved anywhere.  When
  the 48K is in, the loader opens the file again and re-reads each register
  field as it needs it -- like a tape loader rewinding to read the header
  block again.  The FPGA side makes that cheap: "open" restarts the file.
* **Finish with three instructions.**  PC and AF are pushed under the game's
  SP; then every other register is set, and the end is POP AF, (EI), RET.
  EI takes effect only after the next instruction, so the RET always runs
  before any interrupt -- exactly as the real Z80 guarantees.

The compression is a classic run-length code: ED ED nn bb = nn copies of bb.
A lone ED is stored as is, and the byte after it is never the start of a run,
so the decoder never has to look back.


### 7.20 The .tap loader: a second ROM behind a switch

A `.tap` file is a tape recording with the sound taken out: each block is a
2-byte length, the flag byte, the data and an XOR checksum.  The ROM already
knows what to do with blocks -- read the header, print `Program: manic`,
load BASIC, auto-run it, which loads the CODE -- all through one routine,
LD-BYTES at 0556.  So the loader replaces only that routine: patch 0556 with
a jump, hand the ROM each block from the card, and the whole of `LOAD ""`,
`LOAD "" CODE`, `VERIFY` and every game's own loader work unchanged.

That needed room, and the menu had used up the ROM's free 1.1K.  The answer
is the one the divIDE, the Interface 1 and the Beta disk all use: **a second
ROM, paged in by a port pin**.

* **The switch.**  The 8255's PC5 drives the top address line of a 32K ROM.
  Mode word 9Bh (all ports input, as after reset) leaves PC5 floating high:
  bank 0, the stock ROM.  Mode word 91h makes port C an output, which the
  8255 starts at 0: bank 1, the SD ROM.  On a TTL board this is a 74LS74
  driving A14 of a 27256 -- and that is all it is here, too.
* **Doorways.**  The bank changes between two instructions: the OUT is
  fetched from one bank, the next opcode from the other at the next address.
  So every crossing is a pair of addresses lined up in both banks
  (`sdbanks.inc`), all in the stock ROM's empty area.  Going in: bank 0
  `PUSH AF / LD A,91h / OUT` falls through into bank 1's `JP menu`.  Coming
  out: bank 1 `LD A,9Bh / OUT` falls through into bank 0's `POP AF / RET`
  (or RETN, or EI / RET).  AF is pushed on the way in because the doorway
  needs A; the far side pops it back.
* **The trap.**  0556 now jumps to a doorway.  In bank 1, `tapld` asks the
  card bridge "is a tape inserted?"; if not, it goes back out through a
  doorway that runs the three instructions the jump replaced and continues
  at 0559 -- the real tape input still works.  If one is, it reads the next
  block, checks the flag and the checksum as the ROM would, and leaves
  through LD-BYTES' own exit (053F, which restores the border and tests
  BREAK) with carry set or clear.

Three bugs on the way, each of an old kind:

* **Fall-through.**  `choose` ended `CP 'Z' / JP NZ,sel`, and the .z80
  loader came next.  The .tap code was inserted in between, so a .Z80 fell
  into it and showed "Tape in".  The step 4 testbench caught it -- because it
  was run again on the new ROM.  A fall-through is an invisible wire; make it
  a jump the day you write it.
* **A clobbered register.**  The ROM passes the byte count in DE; `tapld`
  read the block length with `rdde`, which returns in DE.  Every block then
  "failed" and LOAD waited forever on a blank screen.  On a TTL board: two
  sources driving one latch.  Write down, per routine, which registers it
  uses -- and check each caller against it.
* **A testbench that typed too fast.**  The menu reads the keyboard only
  after drawing the selection bar; while a page was being read from the
  card, the testbench's key taps went nowhere and the paging test failed
  with nothing wrong in the design.  The fix was in the test: wait for the
  bar (the menu's "ready" signal) before each key -- handshake, don't guess
  delays.

### 7.21 Sound over HDMI: a third kind of period in the blanking

DVI, which our first HDMI output was, sends only two kinds of period: video
(one 10-bit TMDS word per pixel per lane) and control (blanking, where the
two syncs ride on lane 0 as one of four special words).  HDMI adds a
third, the **data island**, placed in the horizontal blanking.  In TTL
terms the blanking interval was a dead bus; HDMI puts a second device on
it, time-multiplexed, with its own framing.

* **Framing.**  Before an island: 8 pixels of *preamble* (control words
  with CTL3..0 = 0101; 0001 announces video instead), then 2 pixels of
  *guard band* (fixed words).  After it, two more guard pixels.  The
  monitor's receiver is a state machine keyed on those patterns, like a
  UART spotting a start bit.
* **Coding.**  Inside the island each lane carries 4 bits per pixel, coded
  into 10 (TERC4): 16 words chosen to be easy to tell apart, at the cost of
  bandwidth.  Lane 0 keeps HSYNC and VSYNC in bits 0-1, so the syncs never
  stop; bit 3 is 0 on an island's first pixel only.  (Upstream sent 1
  throughout -- the testbench caught it.)
* **Packets.**  An island is a run of 32-pixel packets: a 3-byte header
  and four 7-byte subpackets, each with a BCH error-correcting code
  (generator 1+x^6+x^7+x^8 -- a CRC-like shift register, as on a floppy
  controller).  Ours sends four packets per line, chosen by
  `packet_picker`:
  * *audio clock regeneration* (N = 6144, CTS = 27000 at 27 MHz): the
    monitor rebuilds 48 kHz as pixel clock x N / (128 x CTS) -- a PLL
    reference sent as numbers;
  * *audio samples*: up to four stereo samples per packet;
  * *InfoFrames* once a field: AVI (what the video is), audio (2 channels,
    48 kHz), product description ("Krasnod" / "Krasnodar-48", game).
* **The beeper as samples** (`beeper_audio.v`).  The Spectrum's sound is one
  bit.  The board's speaker circuit is a transistor, the speaker's own
  inertia (a low-pass) and a coupling capacitor (a high-pass).  The
  digital copy has the same three parts:
  1. 48 kHz from 27 MHz (27e6 / 48e3 = 562.5): a counter stepping by 2
     that wraps at 1125 gives periods of 562 and 563 alternately -- a
     fractional divider, as in a baud-rate generator;
  2. an *integrator* over each sample period (+16 per clock while high,
     -16 while low): the RC in front of an ADC, so fast toggling becomes an
     in-between level rather than aliasing into whistles;
  3. a *one-pole high-pass*, y = x - x' + y - y/256: the coupling
     capacitor, removing the DC level the bit rests at.

  The sample changes when `clk_audio` falls and is taken when it rises:
  change data on one edge, clock it on the other.

The raster is not a standard mode (896 x 624 at 48.29 Hz).  The islands
are placed using the scan doubler's own counters, and the AVI frame names
the nearest CEA mode (17, 576p50).  The monitor played the sound at the
first try.

The testbench (`tb_hdmi_audio.v`) is the monitor's side written out:
* it decodes every TMDS word back into pixels, guard bands, preambles and
  TERC4;
* it checks each packet's ECC and each InfoFrame's checksum;
* it reads N and CTS;
* it lines the received samples up against the ones sent.

One more lesson from this step.  After the new build went on the board,
.tap games "did nothing".  The new build was the obvious suspect, but
loading **the previous bitstream** first showed the same failure.  So it
was not the build.  Typed again step by step, `LOAD ""` loaded the game:
the fault was in how it had been typed.

### 7.22 One ENTER: making the ROM type LOAD "" for you

The .tap loader needed `LOAD ""` typed after choosing the tape: J, Symbol
Shift+P twice, ENTER, each key held long enough for the ROM's debounce.
That is easy to get wrong (7.21's scare was exactly that). The menu now
does it itself, in the SD ROM, with no hardware change.

**Where to hand over.** The ROM's main loop is short (`12A9`-`1303`):

    12A9  SET-MIN            clear the edit line
    12AC  CHAN-OPEN #0       keyboard / lower screen
    12B1  CALL EDITOR        wait for keys until ENTER
    12B4  CALL LINE-SCAN     syntax check of the edit line
          ...                run it (LINE-RUN), report, loop

The editor's only output is the edit line in memory (`E_LINE`) and its
return to 12B4. So the menu writes `EF 22 22 0D 80` (the token LOAD, two
quote marks, ENTER, the end marker) at `E_LINE` and jumps to 12B4. The
interpreter cannot tell that line from a typed one. In TTL terms, we are
feeding a parallel load into a shift register instead of clocking the bits
in one by one through the keyboard.

**A known state first.** Jumping to 12B4 is only sound if the system is
where the editor would leave it: the stack, `ERR_SP` (where an error
report returns to), the channels, the pointers that lay out BASIC's
memory. F12 may have stopped a game that overwrote all of that. So the
menu first does what the ROM does at power-on (`START`, 11CB-12A9), step by
step in the ROM's order, with each step's ROM address beside it in
`sdmenu.asm`. It leaves out two things:
* the memory test, which takes 1.8 s here. The test leaves RAM zeroed, and
  some of `START` relies on that, so the menu zeroes the system variables
  itself.
* the copyright message.

Any BASIC program in memory is lost, as at power-on, which suits "load
this game".

**Calling across the bank switch.** Some steps are routines that exist only
in the stock ROM (CLS, CHAN-OPEN, a copy of the channel table), and the
menu runs in the other bank. The fix is a "far call", `far0`:

    bank 1: push E_BK, push the routine, push AF; LD A,9Bh / OUT   (X_RET)
    bank 0: POP AF / RET          -> the routine runs, then RETs to E_BK
    bank 0: E_BK: PUSH AF / LD A,91h / OUT
    bank 1: B_BK: POP AF / RET    -> back in the menu, after CALL far0

It is the same doorway trick as before. The routine's own RET is pointed
at a doorway that switches back.

Two side notes:
* The copies come from the ROM's own tables. `LDIR / RET` at 33C3 (the end
  of MOVE-FP) is used as a ready-made "copy BC bytes" routine.
* One mistake was caught before the build: ATTR_P is 5C8D and ATTR_T is
  5C8F, and `MASK_P - 1` pointed at the wrong one. Check a system
  variable's address against the table, not against your memory of the
  table.

### 7.23 720p: a line tripler, one PLL, and a sync that must not land in the sound

The 576p picture is 4:3, so a 16:9 monitor shows black bars at the sides.
The aim: a 16:9 mode, the Spectrum at its own shape, and the border colour
out to the screen edges.

**Size first.** Integer scaling only -- 2.5x makes every other pixel wider
and scrolling text shimmers. At 1280x720, 2x2 left the paper only half the
screen tall; 3x3 makes it 768x576, 80% of the height. That costs border:
720 / 3 = 240 Spectrum lines, so 24 border lines above and below the paper
show instead of 48. The sides get more than enough: each line's first and
last pixel are simply repeated to the edge. The border is one colour per
line anyway, so that *is* the border -- loading stripes included.

**Frame lock, again.** The doubler works because one board line is exactly
two output lines: nothing drifts, nothing tears, a two-line buffer is
enough. The tripler wants exactly three, so the pixel clock must be a whole
multiple of the board's 13.5 MHz: 6 x 13.5 = 81 MHz, an output line of
896 x 6 / 3 = 1792 clocks, and 3 x 312 = 936 lines a frame. The other way --
standard 720p at 74.25 MHz, which is 5.5 x 13.5 -- would need lines that
don't divide evenly and a buffer of dozens of lines to absorb the slip,
more block RAM than the chip has left (42 of 46 used).

In TTL terms: two 74LS161 counter chains clocked from one crystal through
different dividers stay in step for ever; from two crystals they creep
apart and you need a FIFO between them.

**One PLL.** 81 MHz needs a 405 MHz serialiser clock, and the PLL has a
divide-by-3 output: 405 / 3 = 135 MHz, the board clock we already use. So
one PLL makes all three, and the board's 13.5 MHz becomes the 135 MHz
divided by 10 (a counter, as in the old 14 MHz build), not the crystal
halved: the PLL's /3 output keeps no fixed phase to the crystal, and
sampling one with the other failed timing.

**Check the monitor before writing the design.** Three small bitstreams
answered the risky questions first: does the monitor take 1280x720 with
936 lines at 48.3 Hz? (yes, at 74.25 and 81 MHz); does it crop the edges?
(no -- a white frame on the outermost pixels was visible all round); does
the board drive 810 Mbit/s per lane? (yes). Each took minutes.

**Testing it.** `tb_tripler.v` feeds the tripler a synthetic board raster
whose every pixel has a known colour (7 x line + pixel), then checks every
pixel of two output frames, the line and frame lengths, and that the
once-a-frame realignment never moves anything. `tb_720p.sh` runs the whole
board: boot, F12, then one 1280x720 frame checked against what the CPU
wrote into screen memory. That check caught the paper 16 pixels right of
centre: the board's window has 64 border pixels on the left and 32 on the
right. (The 576p picture is off-centre by the same amount.) The tripler
now places the paper in the middle; it fills the sides itself anyway.

**The sound that vanished.** Picture fine, games fine, no sound. Narrowed
down one step at a time, each step a small bitstream:

| test | sound? | so |
|---|---|---|
| sound code, standard 720p60, colour bars | yes | the sound code works at 720p |
| sound code, our exact 1792 x 936 at 81 MHz | yes | the monitor accepts our timing |
| the Spectrum build, a test tone mixed in | no | not the beeper -- the raster source |

Everything that differed was the tripler driving the HDMI counters. Once
a frame it realigns them to the board's line start, which crosses from the
135 MHz side through a two-flop synchroniser -- and that point was at pixel
1300, *inside* the data islands that carry the sound (they follow the
active pixels, from 1294). Moved to pixel 1600, past the islands, and
told to leave the raster alone when it is within two pixels of where it
should be: sound back. Sticky "slip" flags on two LEDs show the
realignment never has to move anything at 1600. What exactly happened at
1300 was not measured -- the likely story is that the synchroniser's edge
sat near a sampling instant there, and a one-pixel jump inside a packet
breaks its framing while the picture never notices a pixel. The fix
removes both the jump and the place it could do harm.

The TTL lesson: a reset or load pulse into a counter chain should arrive
when the rest of the system is not using the count -- in a blanking
interval, not in the middle of a transfer.

**Same logic, different placement.** One build of the same design would
not load games: its place-and-route had put RAM/ROM-to-CPU paths over
budget at 135 MHz. Gowin's timing-driven placement
(`set_option -place_option 1`, `-route_option 1`) cut the failing total
from 170 to 92 ns, cleaned those paths, and games load again. What still
reports failing is the Z80's own logic and its ROM reads, which only
matter on its clock enable, at least 8 clocks apart (habit 13).

### 7.24 Phantom joystick: one port, two jobs

Manic Miner from the `.tap` answered the arrow keys; the same game from
`MANIC.Z80` ignored them. The difference was one byte in the snapshot's
header: "joystick: Kempston". The game then reads I/O port 1F (31) for the
joystick and, when that byte says "moving", ignores the keyboard.

On a real Spectrum a Kempston interface is a 74LS365-style buffer that
puts the five switches on the data bus when the CPU reads port 1F; with
nothing plugged in, its inputs are pulled down and it reads 00. On the
Krasnodar-48, port 1F is the 8255's port A (the 8255 is selected by A7
low, its ports by A5/A6: 1F, 3F, 5F, 7F), brought out on the expansion
connector X3 -- pins A29-A32 and B28-B31 -- presumably for exactly such a
joystick. Our SD loader plugged into that connector and used port A
for the menu's answers, so a game saw whatever the bridge last said, as
if someone were holding the stick.

The fix is a second device on the same connector, sharing it in time:
while bank 1 (the menu) is paged in, port A carries the bridge's answer;
while the stock ROM runs, the connector pulls port A to 00, an idle
joystick. The bank switch already marks which of the two is in charge
(PC5), like a /OE line choosing which of two buffers drives a bus.
`tb_sdmenu.sh` checks the port reads 00 once the game is running.

The TTL lesson: an I/O address is a contract with software you did not
write. Before reusing a port for your own protocol, check what programs
already expect to find there -- and make it return that whenever your
protocol is not running.

---------------------------------------------------------------------------

## 8. Habits worth copying

1. **One clock.**  Sample everything else; detect edges as data (section 6).
2. **Climb the ladder.**  Prove the smallest layer first (section 5).
3. **Make the hardware report.**  LEDs, border colours, sticky error flags.
   A "sticky" checker latches the first error so you see a 1-frame glitch.
4. **Reproduce in simulation before fixing.**  Then the fix is verified, not
   hoped for.
5. **Print events, not waveforms.**  Write the testbench to answer one
   question in a few lines of text.
6. **Suspect everything in turn:** your design, the models, the testbench,
   the tools, the board, the cable.
7. **Change one thing per build**, and keep each bitstream (see
   `bitstreams/`) so you can go back to the last good one.
8. **Never edit generated files**; know your Makefile.
9. **Write down why** next to the code -- the comments in
   `sync_overrides.v` and `fpga_memory.v` say what real-hardware behaviour
   each model reproduces.
10. **Read the timing report's clock list.**  Any clock you did not create
    on purpose is a bug waiting for a build to expose it.
11. **Synchronise before fan-out.**  An asynchronous input goes through two
    flip-flops before any logic sees it.
12. **Clock edges synchronous, resets asynchronous** -- model each the way
    the chip does it.
13. **Same logic, different builds, different results** = timing.  Stop
    changing logic and look at clocks and constraints.
14. **Check every pin in the PnR report after every build** -- "locked: Y"
    and the I/O standard -- not only the pin you changed.
15. **Read the board schematic before choosing a pin.**  "Free on the FPGA"
    is not "free on the board".
16. **Give the design a serial port** when LEDs run out: text logs are
    unambiguous and can be read by the PC (section 7.15).
17. **Predict the resource count before the build, and compare.**  A
    number that did not move (BSRAM 17/46 instead of 33) means the change
    did not get in, whatever the exit code says (section 7.16).
18. **Make the test fail on the old design first.**  A test that has never
    failed has not been shown to test anything.
19. **Read the timing summary after every build**, even when the bitstream
    loads: "works in simulation, dead on the board" is the signature of a
    missed clock (section 7.17).
20. **Give each part the clock it needs**, not the fastest one available.

---------------------------------------------------------------------------
21. **Check the data, not just the shape.**  A test that reads back text but
    not colours passes with every colour wrong.  When only values are wrong,
    disassemble what the assembler actually produced.
22. **Rerun every old test after a change**, not just the new one.  The
    .z80 test found the .tap change's fall-through bug before it reached the
    board.  And give a test a handshake (wait for "ready"), not a delay.
23. **Before debugging a new build, try the last good one.**  Swapping the
    old bitstream back in costs a minute and splits "the change broke it"
    from "something else did" (section 7.21).  It is the board-level
    version of swapping a suspect chip for a known-good one.

24. **Answer the risky question with the smallest build.**  A test pattern
    told us the monitor takes the mode before a line of the design was
    written; two tone-only bitstreams split "the monitor" from "the code"
    (section 7.23).
25. **Keep a correction out of the busy window.**  Realign, reload or reset
    a counter where nothing is reading it -- in blanking, not in the
    middle of a packet -- and don't correct what is already right.

## 9. Glossary

| term | meaning |
|---|---|
| LUT | lookup table: the FPGA's basic logic cell, any function of ~4 inputs |
| flip-flop (FF) | 1-bit storage, updates on a clock edge |
| BSRAM / block RAM | on-chip RAM blocks (used for ROM, DRAM chips, line buffer) |
| PLL | makes new clock frequencies from the 27 MHz crystal |
| clk_sys | our 135 MHz master clock; everything is sampled on it |
| synchronous | all state changes on one clock's edges |
| edge detect | `prev <= x; if (prev && !x) ...` -- sees a falling edge as data |
| Kempston | the common Spectrum joystick interface: port 1F, bits 0-4 = right, left, down, up, fire, 1 = pressed |
| data island | HDMI packets (audio, InfoFrames) sent in the blanking, between the syncs |
| TERC4 | the 4-bit-to-10-bit code used inside data islands |
| race | result depends on which of two simultaneous signals arrives first |
| netlist | list of chips and the wires between them |
| testbench | simulation-only Verilog that drives and observes the design |
| synthesis | Verilog -> logic cells |
| place & route | logic cells -> physical locations and wires; checks timing |
| bitstream (.fs) | the file that configures the FPGA |
| SRAM load / flash | temporary (lost at power-off) / permanent configuration |
| /RAS, /CAS | DRAM row / column address strobes (active low, hence "/") |
| T-state | one Z80 clock cycle (3.5 MHz -> 286 ns) |
| TMDS | the encoding HDMI uses on its wires |
| scan doubler | buffers a 15 kHz TV line and sends it twice at 31 kHz |
| line tripler | the same, three times: each board line becomes three 720p lines |
| frame lock | output and input rasters from one clock, so a frame is exactly a frame |
| VIC | Video Identification Code in the AVI InfoFrame; 0 = not a standard format |
| timing-driven placement | place & route that puts the slowest paths first (Gowin `place_option 1`) |
| derived clock | a logic signal used as a clock -- unanalysed, build-dependent |
| clock enable (cen) | a flip-flop on the main clock that only updates when cen=1 |
| synchroniser | two flip-flops in a row that bring an async signal into a clock domain |
| SDC | timing-constraints file: clocks, multicycle and false paths |
| multicycle path | a path allowed more than one clock period to settle |
| OSER10 / CLKDIV | Gowin's 10:1 serialiser and clock divider, used for HDMI |
| propagation delay (tpd) | time from a chip's input change to its output change |
