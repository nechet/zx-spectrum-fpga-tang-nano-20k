#!/usr/bin/env python3
"""Check the chip models' pin directions against the schematic's own symbols.

The EasyEDA library the board was drawn with names the functional pins of each
symbol -- Q, -Q, C, R, D, S, CE -- alongside the DIP pin number.  That is an
independent statement of which pin does what, drawn by whoever captured the
board, and it can be compared against the Verilog models pin by pin.

This exists because two model bugs got through review by eye and cost a full
hardware cycle each: the CD4015's two halves are interleaved in the package
(CLOCK A is pin 9, CLOCK B is pin 1) and the model had them the other way, and
the К561ТМ2's second half is *not* pinned like a CD4013, which makes reading
from the datasheet actively wrong here.  Neither produces a warning from any
tool -- the design simulates, synthesises and fits, and the picture is simply
missing.

Usage:  verify_pinout.py SCHEMATIC.json [MODELS.v ...]
"""

import json
import re
import sys

from bus_resolve import port_directions

# What each symbol pin name means.  Anything not listed carries no direction
# information here and is skipped: bare numbers on the gate packages, supply
# pins, and -- deliberately -- everything of the form A<n>/B<n>/D<n>, because
# the same spelling is an address input on a memory, a data pin on the CPU and
# a mux channel on a '157.  A global name-to-direction table cannot tell those
# apart, so this only checks the names that mean one thing throughout.
INPUTS = {
    'C', 'CLK', 'SYN',                       # clocks
    'R', 'S', 'RES', 'RESET',                # reset / set
    'CE', 'SE', 'SE0', 'SE1', 'SES', 'EL',   # chip and output enables
    'E', 'E0', 'E1', 'E2', 'EO', 'Ea', 'Eb',
    'EN', '-EN', 'OE-', 'CS-', '-CS', 'PGM', 'WPP',
    'S', 'Sa', 'Sb', 'A/B', 'LD', 'U', 'DN', # selects
    'RAS', 'CAS', 'WE', 'DI',                # DRAM
    '-WR', '-RD', 'INT', 'NMI', 'WAIT', 'BUSRQ',
}
OUTPUTS = {
    'Q', '-Q', 'DO', 'CO', 'BO',
    'Q0', 'Q1', 'Q2', 'Q3', 'Q4',
    '-Q1', '-Q2', '-Q3', '-Q4',
    'Y0', 'Y1', 'Y2', 'Y3', 'Y4', 'Y5', 'Y6', 'Y7', 'Y8',
    'MREQ', 'IORQ', 'RD', 'WR', 'M1', 'RFSH', 'HALT', 'BUSAK',
}

# A direction check cannot catch two inputs of the same part being swapped --
# which is how the 74298's channels were wrong: A1 is pin 3 and B1 is pin 4,
# but A2 is pin 2 and B2 is pin 1, so pins 2 and 4 belong to different
# channels and pairing them by position looks entirely reasonable.  Read the
# symbol's names when writing a model; they are the authority, not a Western
# datasheet for the nearest equivalent part.

LIB_RE = re.compile(r'~(D\d+)(?:\.(\d+))?~')   # single-part symbols have no .n
NAME_RE = re.compile(r'spiceSymbolName`([^`~]*)')


def symbol_pins(shape):
    """[(function, dip_pin)] for one subpart's LIB block."""
    out = []
    for sub in shape.split('#@$'):
        if not sub.startswith('P~'):
            continue
        segs = sub.split('^^')
        texts = []
        for s in segs[1:]:
            f = s.split('~')
            if len(f) >= 7 and f[0] == '1':
                texts.append(f[4])
        if len(texts) != 2:
            continue
        a, b = texts
        # the DIP pin is the numeric one; the other is the function
        if a.isdigit() and not b.isdigit():
            out.append((b, a))
        elif b.isdigit() and not a.isdigit():
            out.append((a, b))
    return out


def main():
    src, *models = sys.argv[1:]
    doc = json.load(open(src))
    shapes = doc['schematics'][0]['dataStr']['shape']

    dirs = {}
    for path in models:
        dirs.update(port_directions(open(path).read()))

    # refdes -> model name, from the generator's own table
    from easyeda_to_verilog import DEVICES

    parts = {}
    for sh in shapes:
        if not sh.startswith('LIB'):
            continue
        m = LIB_RE.search(sh)
        if not m:
            continue
        val = NAME_RE.search(sh)
        if not val or val.group(1) not in DEVICES:
            continue
        mod = DEVICES[val.group(1)][0]
        parts.setdefault((m.group(1), mod, val.group(1)), []).extend(symbol_pins(sh))

    bad = checked = 0
    seen = set()
    for (ref, mod, val), pins in sorted(parts.items()):
        if mod not in dirs or mod in seen:
            continue
        for func, pin in pins:
            want = ('input' if func in INPUTS else
                    'output' if func in OUTPUTS else None)
            if want is None:
                continue
            got = dirs[mod].get('p' + pin)
            if got is None:
                continue
            checked += 1
            if got != want and got != 'inout':
                bad += 1
                print('  %-10s (%-9s %-7s) pin %-3s is %-6s in the symbol '
                      'but %s in the model' % (mod, val, ref, pin, func, got))
        seen.add(mod)

    print('%d functional pins checked against the symbols, %d disagree'
          % (checked, bad))
    print('(pins named A<n>/B<n>/D<n> are skipped -- see the note in this file)')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
