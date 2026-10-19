# USB keyboard adapter: ps2pico on an RP2040-Zero

[Русская версия: раздел «Переходник USB-клавиатуры» в README.ru.md](../README.ru.md#переходник-usb-клавиатуры)

A Waveshare **RP2040-Zero** running a modified
[ps2pico](https://github.com/No0ne/ps2pico) by No0ne turns any USB keyboard
into a 3.3 V PS/2 keyboard for the Tang Nano 20K. It connects straight to
the FPGA, with no level shifters or transistors.

`ps2pico.uf2` here is ready to flash. It was built from these sources
(since then only a comment has changed).

## Flashing

1. Hold the **BOOT** button on the RP2040-Zero and plug it into a PC by USB.
   It appears as a USB drive named `RPI-RP2`.
2. Copy `ps2pico.uf2` onto that drive. The board restarts with the new
   firmware.
3. Unplug it from the PC. From now on its USB-C port is for the keyboard,
   through a USB-C OTG adapter.

## Wiring to the Tang Nano 20K

```
        USB keyboard
             |
      USB-C OTG adapter
             |
   +---------------------+                 +----------------------+
   |    RP2040-Zero      |                 |   Tang Nano 20K      |
   |                     |                 |                      |
   |  GPIO 14  ----+-----|-----------------|--> pin 73  ps2_clk   |
   |  GPIO 10  ----+     |                 |                      |
   |                     |                 |                      |
   |  GPIO 15  ----+-----|-----------------|--> pin 74  ps2_data  |
   |  GPIO 13  ----+     |                 |                      |
   |                     |                 |                      |
   |  GND      ----------|-----------------|--- GND               |
   |  5V       <---------|-----------------|--- 5V  (optional)    |
   +---------------------+                 +----------------------+
```

| RP2040-Zero | Tang Nano 20K | purpose |
|---|---|---|
| GPIO 14 | pin **73** (J6, first hole) | PS/2 clock |
| GPIO 15 | pin **74** (J6, second hole) | PS/2 data |
| GPIO 10 | jumper to GPIO 14, on the RP2040 board | the firmware reads the clock line back |
| GPIO 13 | jumper to GPIO 15, on the RP2040 board | the firmware reads the data line back |
| GND | GND | common ground |
| 5V pad | 5V pin | power for the RP2040 and the keyboard (or a separate 5 V supply, grounds joined) |
| 3V3 pad | **not connected** | never join two regulators' outputs |

* **The two jumpers are required.** Without them the read-back pins float
  low, the firmware thinks the host wants to talk, and it never sends a
  byte. Nothing tells you this: it just stays silent.
* "Pin 73" is the FPGA pin number printed next to the header hole.
* A backlit keyboard or a hub may draw more than the Tang Nano's USB cable
  should carry; use a separate 5 V supply then.

**Status LED** (it latches, does not blink): red = no keyboard; green =
keyboard found, nothing sent yet; blue = the last code sent was a key press;
magenta = the last was a release. While you type it should alternate blue
and magenta. If it stays blue, releases are not getting through.

The FPGA side is described in
[the 20K README](../tang20k/README.md#keyboard).

## Pins, if you change them

Set in `CMakeLists.txt`:

| GPIO | define | signal |
|---|---|---|
| 10 | `CLOCKIN` | reads the clock line |
| 11 | `CLOCKOUT` | clock out, original polarity (into a transistor, for a 5 V host) |
| 12 | `DATAOUT` | data out, original polarity |
| 13 | `DATAIN` | reads the data line |
| 14 | `INVCLOCK` | clock out, true line polarity (direct to a 3.3 V host: this one) |
| 15 | `INVDATA` | data out, true line polarity |

* `DATAOUT` must be `CLOCKOUT + 1`, and `INVDATA` must be `INVCLOCK + 1`:
  each pair is driven as one 2-bit group by a PIO program.
* `CLOCKIN` is also written as a number in `src/ps2phy.pio`
  (`wait 1 gpio, 10`), because the PIO assembler cannot see the C define.
  Change both.

## Building from source

Needs the [Raspberry Pi Pico SDK](https://github.com/raspberrypi/pico-sdk)
2.1.1 or later and an `arm-none-eabi` GCC.

```sh
export PICO_SDK_PATH=/path/to/pico-sdk
mkdir build && cd build
cmake .. && make
# -> build/ps2pico.uf2
```

## What was changed from upstream

Upstream is [No0ne/ps2pico](https://github.com/No0ne/ps2pico) at commit
`2309c5d` ("fix 16kHz output", 2025-07-20). It is made for a Raspberry Pi
Pico driving a 5 V PS/2 host through transistors. Its README is kept as
[README.upstream.md](README.upstream.md).

* **Pins moved to GPIO 10..15.** The upstream defaults don't exist on an
  RP2040-Zero: GPIO 16 drives its onboard RGB LED and GPIO 17 is not
  brought out.
* **True-polarity outputs on GPIO 14/15** (a third PIO program,
  `ps2mirror`). The original outputs are active-high into a transistor
  base, which is inverted relative to the PS/2 line. A 3.3 V host wired
  directly needs the line's own polarity. Both pairs are driven, so one
  binary serves either wiring.
* **Boot protocol instead of report protocol.** In report protocol each
  keyboard sends its own format, and some fell through the parser
  asymmetrically: presses arrived, releases did not, and keys stuck down.
  In boot protocol every keyboard sends the same 8-byte report. The cost is
  six-key rollover, which a Spectrum never notices.
* **The host-to-device path is not started.** Once running it never stops,
  and it flooded the line with repeated frames (11433 in 15 seconds),
  drowning out the keystrokes. The FPGA only listens, so nothing is lost.
* **The status LED latches** (colours above) instead of blinking.

Licence: MIT, copyright (c) 2025 No0ne, see [LICENSE](LICENSE); the changes
are under the same licence.
