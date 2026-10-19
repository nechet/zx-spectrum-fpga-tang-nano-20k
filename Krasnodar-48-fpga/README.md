# Krasnodar-48 — conversions and FPGA work

Everything here is derived from the upstream project in `../Krasnodar-48/`,
which is left exactly as cloned. Nothing in this folder modifies it; the
EasyEDA schematic there is read-only input.

| | |
|---|---|
| `KiCad/` | the board as a KiCad schematic, Soviet parts as drawn |
| `KiCad-US/` | the same board with Western parts and ANSI gate symbols |
| `Verilog/` | structural Verilog netlist of the board, and FPGA resource figures |
| `Tools/` | the converters and the part-equivalence table |

## Regenerating everything

```
SRC=../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json

PYTHONPATH=Tools python3 Tools/easyeda_sch_to_kicad.py $SRC KiCad    Krasnodar-48
PYTHONPATH=Tools python3 Tools/easyeda_sch_to_kicad.py $SRC KiCad-US Krasnodar-48-US --ansi
PYTHONPATH=Tools python3 Tools/easyeda_to_verilog.py  $SRC Verilog/krasnodar48.v
PYTHONPATH=Tools python3 Tools/easyeda_to_verilog.py  $SRC Verilog/krasnodar48_synth.v krasnodar48_synth --synth
```

## Checking the conversion

The whole thing rests on one claim: the converted schematics carry the same
connectivity as the EasyEDA source. That is checked, not asserted:

```
$ PYTHONPATH=Tools python3 Tools/verify_netlist.py $SRC \
      KiCad/Krasnodar-48.kicad_sch KiCad-US/Krasnodar-48-US.kicad_sch

EasyEDA source : 256 multi-pin nets, 156 components
  Krasnodar-48.kicad_sch       256 nets, 256 identical to source   OK
      VCC  124 nodes
      GND  137 nodes
  Krasnodar-48-US.kicad_sch    256 nets, 256 identical to source   OK
      VCC  124 nodes
      GND  137 nodes
```

Nets are compared as sets of (reference, pin) — net *names* differ between the
tools and do not matter, membership does. The VCC and GND counts are printed
because a silent merge of those two rails is the failure this conversion is
most prone to, and did in fact happen once during development.

Simulate the board netlist with `cd Verilog && make run`; FPGA resource
figures with `cd Verilog/synth && make all`.

## Tools needed

`../install-kicad.sh`, `../install-sim.sh`, `../install-fpga.sh`.
