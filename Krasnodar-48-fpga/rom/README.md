# ROM images

The Krasnodar-48 fits a single 27C128 (16 KB) holding the standard **ZX
Spectrum 48K ROM** — the board's own README describes it as replacing the two
РФ4 EPROMs of the original with one part.

## What is here

`spectrum48.hex` is generated locally, not committed:

```
python3 ../Tools/rom2hex.py <your 48.rom> spectrum48.hex
```

On this machine it was cut from the first bank of a four-bank image already in
the tree:

```
python3 ../Tools/rom2hex.py ../../AtlasdFPGA-zx/sidi/zx.rom spectrum48.hex \
        --offset=0 --size=16384
```

That bank is the canonical 48K ROM — `sha1 5ea7c2b824672e914525d1d5c419d71b84a426a2`,
which matches the `48.rom` used across emulators and FPGA cores. The other
three banks of that file are DivMMC firmware and the two 128K ROMs, none of
which this board uses.

## Licensing — why no ROM image is committed

The Spectrum ROM is **copyright Amstrad**, not public domain. Amstrad has
long permitted free redistribution for emulation, but it is not ours to ship,
so `rom/*.hex` and `rom/*.rom` are in `.gitignore`.

Download it from the Fuse emulator, which carries Amstrad's permission:
<https://sourceforge.net/p/fuse-emulator/fuse/ci/master/tree/roms/48.rom?format=raw>
(sha1 `5ea7c2b824672e914525d1d5c419d71b84a426a2`). `../../scripts/get_rom.sh`
does that, checks the sum and writes `spectrum48.hex` here and where the
builds read it. Or dump the ROM from a machine you own.

[Amstrad's statement](https://web.archive.org/web/20160119110852/http://www.worldofspectrum.org/permits/amstrad-roms.txt) (Cliff Lawson, 1999, archived by World of
Spectrum): the ROM may be used with emulators if its copyright messages are
left unaltered and it is not sold. *Amstrad have kindly given their
permission for the redistribution of their copyrighted material but retain
that copyright.*

If you want something unambiguously free, **OpenSE BASIC** (Andrew Owen) is a
GPL-licensed, Spectrum-compatible 16 KB ROM that drops into the same socket.

## Using one

```
cd ../Verilog && make run ROM=../rom/spectrum48.hex
```

The netlist executes it from reset — `DI / XOR A / LD DE,$FFFF / JP $11CB` and
on into the RAM test.
