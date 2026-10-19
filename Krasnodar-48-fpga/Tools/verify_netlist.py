#!/usr/bin/env python3
"""Check that a converted KiCad schematic carries the same netlist as the
EasyEDA source it came from.

Exports the netlist with kicad-cli, then compares it with the connectivity
extracted straight from the EasyEDA JSON by easyeda_netlist.py.  Nets are
compared as *sets of (reference, pin)* -- net names differ between the two
tools and do not matter; membership does.

    python3 verify_netlist.py <schematic.json> <file.kicad_sch> [more.kicad_sch ...]

Exit status is 0 only if every schematic matches the source exactly.
"""

import os
import re
import subprocess
import sys
import tempfile

from easyeda_netlist import load


def sexpr(text):
    toks = re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', text)

    def parse(i):
        out = []
        while i < len(toks):
            t = toks[i]
            if t == '(':
                node, i = parse(i + 1)
                out.append(node)
            elif t == ')':
                return out, i + 1
            else:
                out.append(t[1:-1].replace('\\"', '"') if t.startswith('"') else t)
                i += 1
        return out, i

    return parse(0)[0]


def kicad_nets(path):
    """{net name: {(refdes, pin), ...}} from a kicad-cli sexpr netlist."""
    tree = sexpr(open(path, encoding='utf-8').read())[0]
    nets = {}
    for sec in tree:
        if not (isinstance(sec, list) and sec and sec[0] == 'nets'):
            continue
        for net in sec[1:]:
            name, nodes = '', set()
            for e in net[1:]:
                if e[0] == 'name':
                    name = e[1] if len(e) > 1 else ''
                elif e[0] == 'node':
                    d = {k[0]: (k[1] if len(k) > 1 else '') for k in e[1:]}
                    nodes.add((d.get('ref'), d.get('pin')))
            nets[name] = nodes
    return nets


def partition(nets):
    """Multi-pin nets as a set of frozensets -- names discarded."""
    return {frozenset(v) for v in nets.values() if len(v) > 1}


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)

    src, schematics = argv[1], argv[2:]
    parts, ez = load(src)
    want = partition(ez)
    print('EasyEDA source : %d multi-pin nets, %d components'
          % (len(want), len(parts)))

    ok = True
    tmp = tempfile.mkdtemp(prefix='verify_netlist.')
    for sch in schematics:
        out = os.path.join(tmp, os.path.basename(sch) + '.net')
        r = subprocess.run(['kicad-cli', 'sch', 'export', 'netlist',
                            '--format', 'kicadsexpr', '-o', out, sch],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(out):
            print('  %-28s kicad-cli failed: %s'
                  % (os.path.basename(sch), (r.stderr or r.stdout).strip()[:80]))
            ok = False
            continue

        nets = kicad_nets(out)
        got = partition(nets)
        same = got & want
        status = 'OK' if got == want else 'MISMATCH'
        print('  %-28s %d nets, %d identical to source   %s'
              % (os.path.basename(sch), len(got), len(same), status))

        if got != want:
            ok = False
            for n in sorted(want - got, key=len, reverse=True)[:5]:
                print('      only in source : %d nodes %s' % (len(n), sorted(n)[:6]))
            for n in sorted(got - want, key=len, reverse=True)[:5]:
                print('      only in KiCad  : %d nodes %s' % (len(n), sorted(n)[:6]))
        else:
            # the power rails are the ones most likely to be silently merged
            for rail in ('VCC', 'GND'):
                print('      %-4s %d nodes' % (rail, len(nets.get(rail, ()))))

    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
