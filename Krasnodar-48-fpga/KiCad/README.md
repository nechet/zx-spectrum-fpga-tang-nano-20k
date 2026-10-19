# Krasnodar-48 — KiCad schematic

Converted from `../../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json` (EasyEDA 6.5)
with `../Tools/easyeda_sch_to_kicad.py`. Opens in KiCad 9 and 10.

Open `Krasnodar-48.kicad_pro`, or `Krasnodar-48.kicad_sch` directly — the
symbol library is embedded in the schematic, and `sym-lib-table` also
registers `Krasnodar-48.kicad_sym` for editing.

## Verification

The netlist KiCad extracts from this schematic is **identical** to the
connectivity in the EasyEDA source: 256 multi-pin nets and 95 single-pin nets,
every one with the same set of (reference, pin) nodes. ERC reports 3
error-level violations, all of them the usual "no PWR_FLAG on VCC/GND"
complaint.

## What changed in translation

* **Multi-unit parts.** EasyEDA stores each gate as its own component
  (`D2.1` … `D2.6`). These are merged into real KiCad multi-unit symbols, so
  the six inverters of `D2` are units A–F of one `D2`. The original EasyEDA
  designator is kept in the `EasyEDA_Ref` field of each unit.
* **Buses are graphics.** The buses in the source carry no connectivity — every
  wire leaving a bus is named by a net label. A KiCad bus would merge all of
  those nets into one, so buses and bus entries are drawn as graphic lines.
  The picture is unchanged; the netlist is correct.
* **Footprints are empty.** EasyEDA package names (`DIP-40_STD`,
  `R_0.125_7.62`, …) do not exist in any KiCad footprint library; a dangling
  link would break the netlist-to-board flow. The original name is kept in the
  `EasyEDA_Package` field of every symbol, alongside `Manufacturer`, `MPN` and
  `LCSC` where the source had them.
* **Drawing frame.** The EasyEDA title-block frame (and its logo bitmap) is
  dropped in favour of KiCad's own sheet border; title, revision, date,
  company and author are carried into KiCad's title block. Page size is a
  custom 880 × 640 mm to match the original drawing area.
* **Power flags.** EasyEDA GND flags become a `GND` power symbol (`#PWR…`);
  net ports become KiCad global labels.
* **Hidden power pins** are nudged half a grid step off the 1.27 mm connection
  grid. They are invisible in EasyEDA and connect by pin name only, so their
  nominal coordinates are arbitrary — and several of them land exactly on a
  wire. KiCad connects hidden pins geometrically as well as by name, which
  would short VCC to GND.
* **`C'` and `R'`** keep the reference names the original author gave them.
  KiCad's annotator rejects the apostrophe, which is why "Annotate" reports
  two errors. Renaming them would diverge from the board silkscreen and BOM.

## Related

`../Tools/part-equivalents.md` — cross-reference from every Soviet device on
this board to its Western (74LS / 74ALS / CD4000 / Intel) equivalent.
