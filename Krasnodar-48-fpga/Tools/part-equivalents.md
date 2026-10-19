# Krasnodar-48 — Soviet parts and their Western (US) equivalents

Cross-reference for every Soviet/Russian device used in
`../../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json`.

Every row was checked twice: against the **pinout actually drawn in this
schematic** (pin numbers and pin names extracted from the EasyEDA source) and
against published cross-reference tables (sources at the bottom). The
"Pinout" column says whether the drawn pinout is an exact, pin-for-pin match
with the Western part.

**A matching pinout is not the same as a drop-in substitution**, and two rows
here prove it. К561ТМ2's second flip-flop is *not* pinned like a CD4013B, and
the DRAMs need late-write timing that a pinout table says nothing about. Both
are called out below; both caused real faults in the Verilog conversion.

## Series rules

| Soviet series | Western family | Notes |
|---|---|---|
| К555, КР555 | 74LS (SN74LS…) | Low-power Schottky TTL |
| К1533, КР1533 | 74ALS (SN74ALS…) | Advanced low-power Schottky TTL |
| К561, КР561 | CD4000B / MC14000B | Metal-gate CMOS, 3…15 V |
| КР580 | Intel 808x peripherals | |
| КР565 | Dynamic RAM | |

## TTL — К555 / КР555 (→ 74LS)

| Soviet part | Function | Western equivalent | Pinout | Used as |
|---|---|---|---|---|
| К555ЛН1 | Hex inverter | **74LS04** | exact | D2, D8 |
| К555ЛА3 | Quad 2-input NAND | **74LS00** | exact | D6, D19 |
| К555ЛА4 | Triple 3-input NAND | **74LS10** | exact | D13 |
| К555ЛЕ1 | Quad 2-input NOR | **74LS02** | exact | D7 |
| К555ЛИ1 | Quad 2-input AND | **74LS08** | exact | D12, D18 |
| К555ЛЛ1 | Quad 2-input OR | **74LS32** | exact | D4, D5, D64 |
| К555ЛП5 | Quad 2-input XOR | **74LS86** | exact | D14 |
| К555ТМ2 | Dual D flip-flop, preset + clear | **74LS74** | exact | D10, D17 |
| К555ТМ8 | Quad D flip-flop, common clear | **74LS175** | exact | D53, D54 |
| К555ИР16 | 4-bit universal shift register, 3-state | **74LS295** (74LS295B) | exact, DIP-14 | D51, D52, D57, D58 |
| К555КП2 | Dual 4→1 multiplexer | **74LS153** | exact | D65, D66 |
| К555КП11А | Quad 2→1 multiplexer, non-inverting, 3-state | **74LS257** (74LS257A) | exact | D55, D56 |
| К555КП12 | Dual 4→1 multiplexer, 3-state | **74LS253** | exact | D37–D40 |
| К555КП13 | Quad 2-input multiplexer with storage | **74LS298** | exact | D59–D62 |
| К555КП14 | Quad 2→1 multiplexer, inverting, 3-state | **74LS258** | exact | D21, D22 |
| КР555КП16 | Quad 2→1 multiplexer, non-inverting | **74LS157** | exact | D33 |

Notes:

* **КП11 vs КП14** — both are quad 2→1 selectors with 3-state outputs and an
  identical pinout; КП11 = 74LS257 has true outputs, КП14 = 74LS258 has
  inverting outputs. Do not swap them.
* **КП16 vs КП11** — 74LS157 has totem-pole outputs and an active-low strobe,
  74LS257 has 3-state outputs. Same pinout; not interchangeable in circuits
  that rely on the bus being released.
* **К555ИР16 = 74LS295** is the 14-pin part; do not confuse it with the 16-pin
  74LS194/74LS195 universal shift registers.

## TTL — К1533 (→ 74ALS)

| Soviet part | Function | Western equivalent | Pinout | Used as |
|---|---|---|---|---|
| К1533ИД4 | Dual 2→4 decoder / demultiplexer | **74ALS155** (74LS155) | exact | D11 |
| К1533ИЕ7 | 4-bit up/down binary counter | **74ALS193** (74LS193) | exact | D9 |

## CMOS — К561 (→ CD4000B)

| Soviet part | Function | Western equivalent | Pinout | Used as |
|---|---|---|---|---|
| К561ЛА7 | Quad 2-input NAND | **CD4011B** | exact | D31 |
| К561ЛЕ5 | Quad 2-input NOR | **CD4001B** | exact | D41, D50 |
| К561ЛН2 | Hex inverter | **CD4069UB** | exact | D36, D63 |
| К561ТМ2 | Dual D flip-flop, set + reset | CD4013B | **first half only** | D34 |
| К561ИЕ10 | Dual 4-bit binary counter | **CD4520B** | exact | D20, D32 |
| К561ИР2 | Dual 4-stage static shift register | **CD4015B** | exact | D35 |

**К561ТМ2 is not a pin-for-pin CD4013.** The first flip-flop matches
(1=Q, 2=/Q, 3=C, 4=R, 5=D, 6=S), but the second is mirrored:

| | К561ТМ2 | CD4013B |
|---|---|---|
| Q2 | 13 | 12 |
| /Q2 | 12 | 11 |
| CLK2 | 11 | 10 |
| RESET2 | 10 | 13 |

The symbol drawn in this schematic uses the К561ТМ2 order, and the circuit
only makes sense that way: D34 pin 13 drives N$125, which pin 5 reads back.
"Correcting" a model of this part to the CD4013 datasheet leaves N$125 with no
driver at all and stops the vertical timing chain dead. Fitting a real CD4013B
in this socket would need pins 10–13 rewired.

Note on **К561ЛН2**: older Soviet reference books list CD4049 as the
equivalent, but CD4049 is a 16-pin hex inverting *buffer* with a different
pinout. The drop-in part for this board is the 14-pin **CD4069UB**, which
matches the pinout drawn here pin for pin.

## LSI, memory and discretes

| Soviet part | Function | Western equivalent | Pinout | Used as |
|---|---|---|---|---|
| КР580ВВ55 (ВВ55А) | Programmable peripheral interface | **Intel 8255A** (82C55A) | exact | D3 |
| КР565РУ5Д | 64K × 1 DRAM, +5 V only | **4164** (MK4164 / TMS4164 / MB8264) | exact | D23–D30 |
| КР565РУ6Г | 16K × 1 DRAM, +5 V only | **4164** — see note | exact (4164 pinout) | D42–D49 |
| КТ361Б | PNP small-signal transistor | **2N3906**, BC557, BC327 (check pinout!) | — | VT1 |

Notes:

* **Write timing, not just pinout.** This board strobes its DRAM with *late*
  writes -- /WE falls after /CAS, never before -- so the data is taken on the
  /WE edge rather than the /CAS edge. Any substitute part, or any model of
  one, has to support that. A device or model that only latches on /CAS
  discards every write on this board while leaving addresses, data and strobes
  looking perfectly correct.
* **КР565РУ6** is a 16K × 1 DRAM with a single +5 V rail, wired here on the
  4164 pinout (pin 1 NC, pin 8 Vcc, pin 16 Vss) — *not* the three-rail 4116,
  which needs +12 V and −5 V on pins 8 and 1. The practical Western part for
  this position is therefore a **4164**: pin 9 (A7) of D42–D49 is tied low
  precisely so a 64K device can stand in for the 16K one, as the board's own
  README recommends. (The period-correct single-supply 16K×1 part was the
  Intel 2118, but its pin assignment is not verified here, so 4164 is the
  substitution used in the Western-parts schematic.)
* **КТ361** is a KT-26/TO-92-style package but its lead order is **E–C–B**,
  which is *not* the 2N3906 (E–B–C) or BC557 (C–B–E) order. The footprint on
  this board follows КТ361; re-check the pinout before fitting a Western part.

## Parts that are already Western

| Part | Used as |
|---|---|
| Z80 (Zilog Z80 CPU / КР1858ВМ1, T34ВМ1) | D1 |
| 27C128 EPROM | D15 |
| 1N4148 | VD1, VD2, VD3, VD7, VD8, VD9 |

## Not a real device

**D100 "TTL-DIP"** is an unnamed 14-pin DIP outline (GND on 7, Vcc on 14)
used as a placeholder/spare position on the board — it has no equivalent.

## Using these substitutions

`../KiCad-US/` is a second KiCad project with every one of these swaps applied
— same wiring, same netlist (256 of 256 nets identical), Western part numbers,
and real KiCad footprints. The mapping table it is generated from is
`us_parts.py` in this directory.

## Sources

* [chipdip.ru — К555КП11 = SN74LS257](https://www.chipdip.ru/product/k555kp11)
* [chipdip.ru — К555ТМ8 = SN74LS175](https://www.chipdip.ru/product/k555tm8)
* [chipdip.ru — КР1533ИД4 = SN74ALS155](https://www.chipdip.ru/product/kr1533id4)
* [chipdip.ru — КР1533ИЕ7 = SN74ALS193](https://www.chipdip.ru/product/kr1533ie7)
* [chipdip.ru — К555ИР16 = SN74LS295](https://www.chipdip.ru/product/k555ir16)
* [chipdip.ru — КР580ВВ55А = IC8255A](https://www.chipdip.ru/product/kr580vv55a)
* [oootrion.ru — К555КП2 = SN74LS153](https://oootrion.ru/index.php?product_id=2000408&route=product%2Fproduct)
* [prom.ua — К555КП16 = SN74LS157](https://prom.ua/p1163944850-k555kp16-analog-sn74ls157.html)
* [tec.org.ru — К561/КР1561 to CD4000/4500 cross-reference](https://tec.org.ru/publ/spravochnik/mikroskhemy/analogi_serij_40004500_k561kr1561/6-1-0-13)
* [cxem.net — Soviet ICs and their foreign equivalents](https://cxem.net/sprav/sprav48.php)
* [ru.wikipedia.org — К565РУ3 / К565РУ5 / К565РУ6 family](https://ru.wikipedia.org/wiki/К565РУ3)
* [shematok.com — КТ361 characteristics and import equivalents](https://shematok.com/transistor/kt361)
* [ldsound.club — КТ315 / КТ361 equivalents](https://ldsound.club/threads/kt315-i-kt361-kharakteristiki-analogi.542/)
* 74LS / 74ALS / CD4000 pinouts cross-checked against the pin numbers and pin names carried
  in `../../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json` itself.
