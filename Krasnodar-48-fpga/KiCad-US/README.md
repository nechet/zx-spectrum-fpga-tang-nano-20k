# Krasnodar-48 — KiCad schematic, Western parts, ANSI drafting

The same board as `../KiCad/`, redrawn as a US schematic: Western part numbers
(К555ЛА3 → 74LS00, К561ЛН2 → CD4069UB, КР580ВВ55 → 8255A — 28 substitutions
across 156 components), ANSI distinctive-shape gates, datasheet pin names and
overbars for active-low signals.

Open `Krasnodar-48-US.kicad_pro`. The Soviet-parts project in `../KiCad/` is
untouched — this is a separate project, not a replacement.

## Why the wiring is identical

Every substitution is **pin-for-pin**. That was checked against the pin numbers
and pin names carried in the EasyEDA source itself, not just against a
cross-reference table, and it is what makes the swap safe: no pin moves, so no
wire moves.

The netlist proves it — all three agree exactly:

| | multi-pin nets | identical to the EasyEDA source |
|---|---|---|
| EasyEDA source | 256 | — |
| `../KiCad/` (Soviet parts) | 256 | 256 |
| this project (Western parts) | 256 | 256 |

ERC reports 3 error-level violations, all the usual "no PWR_FLAG on VCC/GND".

## What changed

* **Value** is the Western part number; the Soviet one is kept in a new
  `Original_Part` field on every substituted component, so a BOM can show both.
* **Description** on each library symbol says what the part is
  ("Quad 2-input NAND gate", "Dual 4-to-1 multiplexer, 3-state").
* **ANSI distinctive-shape gates.** The ten gate types (74LS00/02/04/08/10/32/86,
  CD4001B/4011B/4069UB) are drawn as AND / OR / XOR / inverter shapes with
  inversion bubbles instead of GOST rectangles with a `&`, `1` or `=1`
  qualifier — 73 arcs and 90 bubbles across the library.
* **Datasheet pin names**, e.g. the 74LS253's `1G`, `1C0…1C3`, `A`, `B`, `1Y`
  where the source had `E1`, `1.0…1.3`, `SE1`, `1`. Active-low pins carry a
  real overbar (63 of them): `~{MREQ}`, `~{CLR}`, `~{OE}`.
* **Box labels** on the MSI parts are the US ones — `MUX`, `DEC`, `CTR`, `SRG`
  — instead of `MS`, `DC`, `CT2`, `RG`.
* **Footprint** is now a real KiCad footprint rather than an empty field —
  18 distinct ones, every one verified to exist in the stock libraries
  (`Package_DIP`, `Resistor_THT`, `Capacitor_THT`, `Diode_THT`, `Crystal`,
  `Connector_PinHeader_2.54mm`, `Connector_Molex`). So this project can drive a
  new PCB layout, which `../KiCad/` could not.

The substitution table lives in `../Tools/us_parts.py`; regenerate with

```
PYTHONPATH=../Tools python3 ../Tools/easyeda_sch_to_kicad.py \
    ../../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json . Krasnodar-48-US --ansi
```

(`--us` does the part substitution only and keeps the original rectangles;
`--ansi` implies `--us` and adds the ANSI drafting. The shapes come from
`../Tools/ansi_symbols.py`, the pin-name and label tables from
`../Tools/us_parts.py`.)

## Things to know before building from this

* **The gate shapes are drawn into the space the old rectangles occupied**, so
  every pin stays exactly where it was and not one of the 1407 wires moved.
  Dropping in KiCad's stock `74xx` symbols instead would have moved every pin
  and forced a full re-route. The consequence is that the *placement* is still
  the original Soviet layout — the shapes are ANSI, the floorplan is not
  redrawn.
* **MSI and LSI parts stay rectangular**, which is US practice: ANSI
  distinctive shapes only exist for basic gates. Those boxes got US labels and
  datasheet pin names instead.
* **КТ361Б → 2N3906 is a lead-order trap.** КТ361 is **E–C–B**; the 2N3906 is
  E–B–C and the BC557 is C–B–E. The symbol is relabelled but its footprint is
  deliberately left empty — choose a land pattern that matches the transistor
  you actually fit.
* **Both DRAM banks are labelled 4164.** The 16K bank (D42–D49, originally
  КР565РУ6Г) is drawn on the 4164 pinout with A7 (pin 9) tied low, precisely so
  a 64K part can be fitted — which is what the board's own README recommends.
* **CD4069UB, not CD4049.** Older Soviet handbooks give CD4049 as the К561ЛН2
  equivalent, but the '4049 is a 16-pin buffer with a different pinout. The
  CD4069UB matches pin for pin.
* **Five packages have no footprint assigned**, because no stock KiCad
  footprint matches closely enough to assign silently:
  `CAP_TH_3.68`, `CAP-TH_BD6.3-P6.00-D0.8-FD`, `D_TH_2.54_V` (the vertical
  DO-35 land pattern depends on which lead is up), `KT315_STD`, and
  `SYS_CONN_32X2_5.08` (the board-specific expansion connector). The original
  package name is still in the `EasyEDA_Package` field of each.
* `C'` and `R'` keep the reference names the original author gave them, so
  KiCad's annotator reports two errors on the apostrophe.

See `../Tools/part-equivalents.md` for every mapping with its sources and the
pinout evidence.
