#!/usr/bin/env python3
"""Extract the netlist from an EasyEDA (v6.x) schematic source JSON.

The connectivity rules implemented here were validated against KiCad: running
the converted schematic (Tools/easyeda_sch_to_kicad.py) through
`kicad-cli sch export netlist` yields exactly the same nets -- same count, same
(reference, pin) membership.

Rules:
  * wire segments join at shared points;
  * any pin / junction / label / wire end lying ON a segment joins it
    (T-junctions), but a *hidden* pin has no graphic and joins by name only;
  * net labels with the same text are one net (single sheet => labels are
    global);
  * hidden power pins join the net named after the pin (VCC / GND);
  * buses and bus entries carry nothing -- every wire off a bus is labelled.

Used as a library (`load()`) or run directly to dump a JSON netlist.
"""

import json
import math
import re
import sys
from collections import defaultdict, OrderedDict


def _k(x, y):
    return (round(float(x), 2), round(float(y), 2))


class Part:
    __slots__ = ('ref', 'value', 'package', 'attrs', 'pins', 'pin_names', 'units')

    def __init__(self, ref):
        self.ref = ref
        self.value = ''
        self.package = ''
        self.attrs = {}
        self.pins = OrderedDict()        # pin number -> net name
        self.pin_names = OrderedDict()   # pin number -> pin name from the symbol
        self.units = []


def _split_attrs(s):
    f = s.split('`')
    return {f[i]: f[i + 1] for i in range(0, len(f) - 1, 2) if f[i]}


def load(path):
    """Return (parts, nets) where parts maps refdes -> Part and nets maps
    net name -> sorted list of (refdes, pin number)."""
    doc = json.load(open(path, encoding='utf-8'))
    shapes = doc['schematics'][0]['dataStr']['shape']

    segs, labels, junctions = [], [], set()
    pins = []            # (point, ref, number, hidden, pin name)
    parts = OrderedDict()

    for s in shapes:
        f = s.split('~')
        t = f[0]
        if t == 'W':
            v = f[1].split()
            for i in range(0, len(v) - 3, 2):
                segs.append((_k(v[i], v[i + 1]), _k(v[i + 2], v[i + 3])))
        elif t == 'J':
            junctions.add(_k(f[1], f[2]))
        elif t == 'N':
            labels.append((_k(f[1], f[2]), f[5]))
        elif t == 'F':
            sub = s.split('^^')
            labels.append((_k(*sub[1].split('~')), sub[2].split('~')[0]))
        elif t == 'LIB':
            head = s.split('#@$')[0].split('~')
            body = s.split('#@$')[1:]
            ref = value = ''
            for p in body:
                g = p.split('~')
                if g[0] == 'T' and g[1] == 'P':
                    ref = g[12]
                elif g[0] == 'T' and g[1] == 'N':
                    value = g[12]
            base = ref.split('.')[0]
            if not any(p.startswith('P~') for p in body):
                continue                      # drawing frame, not a component
            part = parts.setdefault(base, Part(base))
            part.value = part.value or value
            part.units.append(ref)
            attrs = _split_attrs(head[3])
            part.attrs.update(attrs)
            part.package = part.package or attrs.get('package', '')
            for p in body:
                if not p.startswith('P~'):
                    continue
                sub = p.split('^^')
                hd = sub[0].split('~')
                nm = sub[3].split('~') if len(sub) > 3 else []
                nu = sub[4].split('~') if len(sub) > 4 else []
                number = nu[4] if len(nu) > 4 else hd[3]
                pname = nm[4] if len(nm) > 4 else number
                hidden = hd[1] == 'none'
                # A hidden pin has no graphic, so it must not inherit the
                # connectivity of whatever happens to be drawn at its nominal
                # coordinates -- give it a node key of its own.
                node = ('hidden', base, number) if hidden else _k(hd[4], hd[5])
                pins.append((node, base, number, hidden, pname))
                part.pin_names[number] = pname

    # ---------------------------------------------------------------- union-find
    parent = {}

    def find(a):
        parent.setdefault(a, a)
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for a, b in segs:
        union(a, b)

    attach = set(junctions)
    for a, b in segs:
        attach.add(a)
        attach.add(b)
    for p, _r, _n, hidden, _pn in pins:
        if not hidden:
            attach.add(p)
    for p, _n in labels:
        attach.add(p)

    CELL = 50.0
    buckets = defaultdict(list)
    for i, (a, b) in enumerate(segs):
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        for gx in range(int(math.floor(x0 / CELL)), int(math.floor(x1 / CELL)) + 1):
            for gy in range(int(math.floor(y0 / CELL)), int(math.floor(y1 / CELL)) + 1):
                buckets[(gx, gy)].append(i)

    def on_seg(p, a, b):
        if abs((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) > 1e-6:
            return False
        return (min(a[0], b[0]) - 1e-6 <= p[0] <= max(a[0], b[0]) + 1e-6 and
                min(a[1], b[1]) - 1e-6 <= p[1] <= max(a[1], b[1]) + 1e-6)

    for p in attach:
        cell = (int(math.floor(p[0] / CELL)), int(math.floor(p[1] / CELL)))
        for i in buckets.get(cell, []):
            a, b = segs[i]
            if on_seg(p, a, b):
                union(p, a)

    by_name = defaultdict(list)
    for p, n in labels:
        by_name[n].append(p)
    for n, ps in by_name.items():
        for p in ps[1:]:
            union(ps[0], p)

    hidden_by_name = defaultdict(list)
    for p, _r, _n, hidden, pname in pins:
        if hidden and pname:
            hidden_by_name[pname].append(p)
    for n, ps in hidden_by_name.items():
        anchor = by_name[n][0] if by_name.get(n) else ps[0]
        for p in ps:
            union(p, anchor)

    # ---------------------------------------------------------------- name nets
    root_name = {}
    for n, ps in by_name.items():
        root_name.setdefault(find(ps[0]), n)
    for n, ps in hidden_by_name.items():
        root_name.setdefault(find(ps[0]), n)

    nets = defaultdict(list)
    anon = 0
    for p, ref, number, _hidden, _pn in pins:
        r = find(p)
        if r not in root_name:
            anon += 1
            root_name[r] = 'N$%d' % anon
        name = root_name[r]
        nets[name].append((ref, number))
        parts[ref].pins[number] = name

    return parts, {k: sorted(set(v)) for k, v in nets.items()}


if __name__ == '__main__':
    parts, nets = load(sys.argv[1])
    out = {
        'parts': {r: {'value': p.value, 'package': p.package,
                      'units': p.units, 'pins': p.pins,
                      'pin_names': p.pin_names} for r, p in parts.items()},
        'nets': nets,
    }
    print(json.dumps(out, ensure_ascii=False, indent=1))
