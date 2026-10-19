#!/usr/bin/env python3
"""Check every pin of the generated Verilog against the schematic.

The Verilog netlist is a transcription, so the only thing that makes it
trustworthy is a comparison back to the source.  `verify_netlist.py` does this
for the KiCad output; this does the same for the Verilog, pin by pin:

    for each chip instance, for each `.pN(net)`, is `net` what the schematic
    has on pin N of that chip?

A wrong pin here is close to undetectable by any other means -- it simulates,
it synthesises, and it produces a machine that is subtly wrong somewhere in the
middle of the video timing.

Usage:  verify_verilog_netlist.py SCHEMATIC.json NETLIST.v [NETLIST.v ...]
"""

import re
import sys

from easyeda_netlist import load
from easyeda_to_verilog import ident, inst_ident

INST_RE = re.compile(r'^[ \t]*(\w+)[ \t]*(#\s*\(.*?\))?[ \t]*(U_\w+)[ \t]*\((.*?)\)[ \t]*;',
                     re.S | re.M)
CONN_RE = re.compile(r'\.(p\d+)\s*\(\s*([^()]*?)\s*\)')

# The generator ties the supply pins to constants rather than naming a net.
CONST = {"1'b0": {'GND'}, "1'b1": {'VCC', 'VDD'}}


def main():
    src, *netlists = sys.argv[1:]
    parts, nets = load(src)

    # (refdes, pin) -> net name
    pinnet = {}
    for name, pins in nets.items():
        for ref, pin in pins:
            pinnet[(ref, str(pin))] = name

    bad = total = 0
    for path in netlists:
        with open(path) as f:
            text = f.read()
        checked = missing = 0
        for m in INST_RE.finditer(text):
            inst = m.group(3)
            ref = None
            for r in parts:
                if inst_ident(r) == inst:
                    ref = r
                    break
            if ref is None:
                continue
            for pin, expr in CONN_RE.findall(m.group(4)):
                want = pinnet.get((ref, pin[1:]))
                if want is None:
                    missing += 1
                    continue
                checked += 1
                total += 1
                if expr in CONST:
                    ok = want in CONST[expr]
                else:
                    ok = (expr == ident(want))
                if not ok:
                    bad += 1
                    print('  %-22s %-4s -> %-14s schematic says %s'
                          % (ref + ' (' + inst + ')', pin, expr, want))
        print('%-34s %4d pins checked, %d not in schematic'
              % (path.split('/')[-1], checked, missing))

    print('\n%d pins checked, %d wrong' % (total, bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
