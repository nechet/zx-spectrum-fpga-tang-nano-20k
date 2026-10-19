# Krasnodar-48 on the Tang Nano 20K: technical notes

The Tang Nano 20K design (GW2AR-LV18QN88C8/I7, GW2A-18C): video, sound,
keyboard and SD card loader around the board netlist in `../core`. For
building and using it, see the [top-level README](../README.md). How
everything works, explained from the logic-chip side:
[LEARNING.md](LEARNING.md).

## Builds

Gowin projects, built with `./build.sh <folder>` (or `../scripts/build.sh`).
`build.sh` fails on any Gowin `ERROR` or a stale `.fs`, and prints the
timing summary, BSRAM use and every pin's lock state.

| folder | what | output |
|---|---|---|
| `gowin_sd720/` | **the main build**: 1280x720, sound, SD loader, PS/2 keyboard (`HDMI_720P`) | `krasnodar_20k_sd720.fs` |
| `gowin_sd/` | the same at 720x576 with the scan doubler | `krasnodar_20k_sd.fs` |
| `gowin/` | the bare 48K machine with the PS/2 keyboard, 576p, no SD or sound | `krasnodar_20k.fs` |
| `gowin_sdtest/` | SD card test: FAT32 listing (or raw sectors) on the USB serial port | `krasnodar_20k_sdlist.fs` |
| `gowin_hdmi720/`, `gowin_hdmi720_81/` | 720p test pattern; S2 steps through layouts and timings | `bitstreams/hdmi_test_720p*.fs` |
| `gowin_hdmi720a_60/`, `gowin_hdmi720a_tri/` | 720p sound test: colour bars and a beeping tone | `bitstreams/hdmi720_audio_*.fs` |

The features are switched by `defines.v` in each folder: `RAM48`,
`PS2_KBD`, `SD_LOADER`, `ROM_BANKS`, `HDMI_AUDIO`, `HDMI_720P`. The
keyboard pins can be moved to 25/26 with `PS2_PINS=25_26` (see below).

## Clocks and video

The board's raster is 896 clocks by 312 lines whatever it runs at. Its
master clock is 13.5 MHz, 3.6 % below the 14 MHz it was designed for, so
that every clock comes from the crystal in whole ratios and the HDMI
picture is locked to the board's frame: no frame buffer, no tearing.

| build | board logic | pixel clock | raster (total) | active | per board line |
|---|---|---|---|---|---|
| 720p | 135 MHz = 405 / 3 | 81 MHz = 405 / 5 | 1792 x 936 | 1280 x 720 | 3 output lines |
| 576p | 135 MHz (PLL x5) | 27 MHz = 135 / 5 | 896 x 624 | 720 x 576 | 2 output lines |

Both run at 48.29 Hz. The board's logic runs on 135 MHz with clock enables
at the 13.5 MHz board rate (one clock domain, edges detected as data).

**720p** (`scan_tripler.v`): each Spectrum pixel is 3 x 3 screen pixels.
The paper (768 x 576) is centred; 24 border lines show above and below
it; the 16:9 sides repeat each line's first and last pixel, so the border
reaches the screen edges. Two 352-pixel line buffers ping-pong, one block
RAM. One PLL (`pll_405.v`) makes 405 MHz for the serialisers, and its /3
output is the board's 135 MHz. The once-a-frame realignment sits at pixel
1600, past the HDMI data islands, and leaves the raster alone when it is
within two pixels of where it should be.

**576p** (`../core/scan_doubler.v`): every board line shown twice; the
visible 704 samples resampled onto 720 pixels.

**Sound** (`beeper_audio.v`, `hdmi_audio_out.sv`): the beeper bit (and the
tape output, quieter) becomes 48 kHz 16-bit samples (fractional divider,
integrator, DC-blocking high-pass) sent in HDMI data islands in the
horizontal blanking, at most four packets an island. The AVI InfoFrame
declares VIC 0 at 720p (not a standard format) and VIC 17 at 576p. Packet
code: `third_party/hdmi/` ([hdl-util/hdmi](https://github.com/hdl-util/hdmi),
see its `PROVENANCE.md`).

## Pins

| signal | pin | notes |
|---|---|---|
| `clk` (27 MHz) | 4 | |
| `rst_i` (button S1) | 88 | idles low; the design's reset is active high |
| `nmi_btn` (button S2) | 87 | opens the games menu, as F12 does |
| `led[0..5]` | 15..20 | active low |
| `tmds_clk_p` | 33 (34) | LVDS25, true LVDS pair |
| `tmds_d_p[0..2]` | 35, 37, 39 (36, 38, 40) | LVDS25 |
| `ps2_clk`, `ps2_data` | 73, 74 | 3.3 V only; header J6, first two holes |
| `sd_clk`, `sd_cmd`, `sd_dat0`, `sd_dat3` | 83, 82, 84, 81 | the on-board microSD slot, SPI mode |

Gowin names a true-LVDS pair once, on the `_p` port, and places the `_n`
half itself (`tangnano20k_gowin.cst`).

### Keyboard

`ps2_rx.v` receives the PS/2 bytes (it only reads the lines, never drives
them); `ps2_zx_keymap.v` maps PC keys onto the Spectrum's 40 keys;
`zx_matrix.v` answers the CPU's row scans on A8..A15 with the column bits.
Shift is CAPS SHIFT, Ctrl or Alt is SYMBOL SHIFT, Backspace is DELETE, the
arrows are CAPS SHIFT + 5..8, and F12 is the menu key.

The lines must be **3.3 V**: the FPGA pins are not 5 V tolerant. A USB
keyboard works through an RP2040-Zero running ps2pico, wired directly:
firmware and wiring in [`../ps2pico/`](../ps2pico/README.md).

Pins 25/26 are a build option (`PS2_PINS=25_26`, bitstream suffix
`_p25_26`): `build.tcl` joins `tangnano20k_gowin.cst` and
`ps2_pins_<pair>.cst` into `combined.cst`, since Gowin reads only one
constraint file. Pin 25 also reaches the HDMI connector's HPD and 26 its
CEC, so a CEC message during a keystroke can cost a keypress; 73/74 go only
to the header, which is why they are the default.

### LEDs (SD builds)

| LED | 576p | 720p |
|---|---|---|
| 0 | the menu has been opened (NMI seen) | same |
| 1 | S2 held | the realignment found the raster 1-2 pixels off (tolerated) |
| 2 | F12 held | the raster was further off after the first lock |
| 3 | SD card mounted | same |
| 4 | SD error | same |
| 5 | heartbeat, about 1 Hz | same |

## SD card loader

* `sd_spi.v`: the card in SPI mode (init, CMD17 single-block reads)
* `fat32.v`: finds the first partition, lists the root folder (8.3 names
  ending `.Z80`, `.SNA`, `.TAP`) and reads files cluster by cluster
* `sd_bridge.v`: connects that to the board's 8255. Port B carries a
  command, port A the answer, port C a strobe/acknowledge pair. Commands:
  mount, first/next game, open, read the next byte, insert tape, "is a tape
  in?" (the list is at the top of `sd_bridge.v`)
* `nmi_gen.v`: F12 or S2 pulls the Z80's /NMI
* the ROM is 32 KB in two banks, paged by the 8255's PC5. Bank 0 is the
  stock 48K ROM with a few "doorways" (`sdrom0.asm`), bank 1 the menu and
  loaders (`sdmenu.asm`); `sdbanks.inc` holds the doorway addresses.
  `mk_sdrom.py` assembles both (z80asm) into `spectrum48_sd.hex`. The NMI
  handler at 0066 jumps through a doorway into the menu
* `.Z80`: version 1 snapshots, 48K, compressed or not (`z80tov1.py` turns
  48K version 2/3 files into version 1)
* `.TAP`: ENTER inserts the tape, rebuilds BASIC's state as the ROM's own
  start-up does, writes `LOAD ""` into the edit line and hands over to the
  ROM's main loop. LD-BYTES (0556) is trapped and served from the card, so
  every block, including a game's own later loads, arrives instantly
* `.SNA`: listed, not loaded yet
* port A is also port 1F, the Kempston joystick's: it carries the
  bridge's answers only while bank 1 is paged in, and reads 00 (no
  joystick) while a program runs (LEARNING.md 7.24)

## Tests

Icarus Verilog (the system's `iverilog`). Run from this folder, or through
`../scripts/test.sh`.

| script | what it checks |
|---|---|
| `tb_tripler.sh` | the line tripler on a synthetic raster: every pixel of two frames, line and frame lengths, the lock |
| `tb_hdmi_audio.sh [720]` | the HDMI stream decoded as a monitor would: pixels, guard bands, TERC4, ECC, InfoFrames, N/CTS and every audio sample |
| `tb_sdmenu.sh` | the whole board: F12 over PS/2, the menu's text and colours, then a `.z80` load checked byte by byte |
| `tb_sdpage.sh` | the menu's paging |
| `tb_sdtap.sh` | ENTER on a test tape from BASIC: it loads and runs, and its program checks itself |
| `tb_720p.sh` | the whole board at 720p: one 1280x720 frame checked pixel by pixel against screen memory and the border |
| `tb_sdgame.sh` | a real game's tape (`TAPE=...`, not included) up to its entry point, on the audio build |
| `tb_ram48.sh`, `tb_kbd_sys.sh` | the upper 32 KB of RAM; the keyboard path |
| `tb_fat.v`, `tb_sd*.v` | the FAT32 reader and the SD card reader on their own |

The whole-board tests need the ROM (`../scripts/get_rom.sh`) and z80asm.
`mk_fat_image.py` builds the test card image (random filler and the
project's own test programs: `mk_testz80.py`'s snapshot, `mk_testtap.py`'s
tape).

## Files

| | |
|---|---|
| `scan_tripler.v`, `pll_405.v`, `sim_720p.v` | 720p: the line tripler, the one PLL, their simulation models |
| `beeper_audio.v`, `hdmi_audio_out.sv`, `third_party/hdmi/` | sound over HDMI |
| `ps2_rx.v`, `ps2_zx_keymap.v`, `ps2_keyboard.v`, `zx_matrix.v` | PS/2 keyboard |
| `ps2_uart_mon.v`, `uart_tx.v` | keyboard monitor on the USB serial port (diagnostic) |
| `sd_spi.v`, `fat32.v`, `sd_bridge.v`, `nmi_gen.v` | SD card loader hardware |
| `sd_dump.v`, `sd_list.v` | SD test tops (`gowin_sdtest/`) |
| `sdmenu.asm`, `sdrom0.asm`, `sdbanks.inc`, `mk_sdrom.py` | the SD ROM and its build |
| `sd_card_model.v`, `mk_fat_image.py`, `mk_testtap.py`, `mk_testz80.py`, `testsnap.asm` | the SD card model and the test card's contents |
| `tb_*.v`, `tb_*.sh` | testbenches (above) |
| `testrom4.asm`, `testrom5.asm` | test ROMs: keyboard, upper 32 KB of RAM |
| `hdmi720_test.v`, `hdmi720_audio_test.v`, `pll_371.v` | 720p test pattern and sound test |
| `pll_28.v`, `pll_140.v` | optional exact 14 MHz clocking (`CLK14`): 50.08 Hz, two PLLs; not used by the builds |
| `z80tov1.py` | rewrites 48K version 2/3 `.z80` snapshots as version 1, with 8.3 names |
| `bitstreams/` | the test-pattern and sound-test bitstreams (they carry no ROM) |
| `LEARNING.md` | how it works, for someone who knows logic chips |
