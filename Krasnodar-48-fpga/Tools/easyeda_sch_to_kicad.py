#!/usr/bin/env python3
"""
Convert an EasyEDA (v6.x) schematic source JSON into KiCad 9/10 files.

Produces:
    <out>/<name>.kicad_sch   - the schematic
    <out>/<name>.kicad_sym   - symbol library used by the schematic
    <out>/<name>.kicad_pro   - minimal project file
    <out>/sym-lib-table      - so the library resolves when the project is opened

Usage:
    python3 easyeda_sch_to_kicad.py Schematic_xxx.json outdir [ProjectName] [--us]

With --us, every Soviet device is relabelled with its pin-compatible Western
equivalent (К555ЛА3 -> 74LS00 and so on) from Tools/us_parts.py, and KiCad
footprints are assigned where the package maps unambiguously.  The wiring is
untouched: the substitutions are all pin-for-pin, so the netlist is identical.
"""

import json
import math
import re
import sys
import uuid as _uuid
from collections import defaultdict, OrderedDict

# ---------------------------------------------------------------- constants

# EasyEDA schematic unit is 10 mil.
U = 0.254                      # mm per EasyEDA unit
PT = 0.18                      # mm of KiCad text height per EasyEDA "pt"
DEF_TEXT = 1.27                # KiCad default text height (mm)

# EasyEDA electrical pin type -> KiCad pin electrical type
ETYPE = {
    '0': 'passive',
    '1': 'input',
    '2': 'output',
    '3': 'bidirectional',
    '4': 'power_in',
}

NS = _uuid.UUID('6ba7b810-9dad-11d1-80b4-00c04fd430c8')


def uid(*key):
    return str(_uuid.uuid5(NS, '|'.join(str(k) for k in key)))


def num(s, default=0.0):
    try:
        return float(s)
    except (TypeError, ValueError):
        return default


def q(s):
    """Quote a string for an S-expression."""
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def fmt(v):
    v = round(v + 0.0, 4)
    if v == 0:
        v = 0.0
    return ('%.4f' % v).rstrip('0').rstrip('.') or '0'


# ---------------------------------------------------------------- geometry

def rot_screen(dx, dy, deg):
    """Rotate a vector in EasyEDA screen coordinates (y down)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if abs(c) < 1e-9:
        c = 0.0
    if abs(s) < 1e-9:
        s = 0.0
    return dx * c - dy * s, dx * s + dy * c


class Frame:
    """Maps EasyEDA absolute coords to library-local coords of one symbol.

    EasyEDA stores every placed component with absolute, already-rotated
    coordinates.  To recover the un-rotated library drawing we translate by
    the component origin and rotate back; then we flip Y because KiCad symbol
    libraries use a Y-up coordinate system.
    """

    def __init__(self, ox, oy, rot):
        self.ox, self.oy, self.rot = ox, oy, rot

    def pt(self, x, y):
        dx, dy = rot_screen(x - self.ox, y - self.oy, self.rot)
        return dx * U, -dy * U

    def vec(self, dx, dy):
        dx, dy = rot_screen(dx, dy, self.rot)
        return dx * U, -dy * U

    def angle(self, dx, dy):
        dx, dy = self.vec(dx, dy)
        return round(math.degrees(math.atan2(dy, dx))) % 360


def parse_path(d):
    """Very small SVG path reader: returns a list of sub-paths.

    Each sub-path is ('poly', [(x, y), ...]) or ('arc', p0, params, p1).
    Only the commands EasyEDA emits (M, L, H, V, h, v, A, Z) are handled.
    """
    toks = re.findall(r'[MmLlHhVvAaZz]|-?\d*\.?\d+(?:e-?\d+)?', d)
    out, cur, cx, cy, sx, sy = [], [], 0.0, 0.0, 0.0, 0.0
    i, cmd = 0, None
    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t
            i += 1
            if cmd in 'Zz':
                if cur:
                    cur.append((sx, sy))
                    out.append(('poly', cur))
                    cur = []
                cx, cy = sx, sy
            continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == 'M':
            x, y = float(toks[i]), float(toks[i + 1])
            i += 2
            if rel:
                x, y = cx + x, cy + y
            if cur:
                out.append(('poly', cur))
            cur, cx, cy, sx, sy = [(x, y)], x, y, x, y
            cmd = 'l' if rel else 'L'
        elif c == 'L':
            x, y = float(toks[i]), float(toks[i + 1])
            i += 2
            if rel:
                x, y = cx + x, cy + y
            cur.append((x, y))
            cx, cy = x, y
        elif c == 'H':
            x = float(toks[i])
            i += 1
            if rel:
                x += cx
            cur.append((x, cy))
            cx = x
        elif c == 'V':
            y = float(toks[i])
            i += 1
            if rel:
                y += cy
            cur.append((cx, y))
            cy = y
        elif c == 'A':
            rx, ry, xrot, laf, sf = (float(toks[i]), float(toks[i + 1]),
                                     float(toks[i + 2]), float(toks[i + 3]),
                                     float(toks[i + 4]))
            x, y = float(toks[i + 5]), float(toks[i + 6])
            i += 7
            if rel:
                x, y = cx + x, cy + y
            if cur:
                out.append(('poly', cur))
                cur = []
            out.append(('arc', (cx, cy), (rx, ry, xrot, laf, sf), (x, y)))
            cur, cx, cy = [(x, y)], x, y
        else:                                       # unsupported -> skip
            i += 1
    if len(cur) > 1:
        out.append(('poly', cur))
    return out


def arc_mid(p0, params, p1):
    """Midpoint of an SVG elliptical arc (treated as circular)."""
    (x0, y0), (rx, ry, _xrot, laf, sf), (x1, y1) = p0, params, p1
    r = max(abs(rx), abs(ry), 1e-6)
    dx, dy = (x1 - x0) / 2.0, (y1 - y0) / 2.0
    d = math.hypot(dx, dy)
    if d < 1e-9:
        return (x0, y0)
    r = max(r, d)
    h = math.sqrt(max(r * r - d * d, 0.0))
    mx, my = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    ux, uy = -dy / d, dx / d
    sign = 1.0 if (laf != sf) else -1.0
    ccx, ccy = mx + sign * h * ux, my + sign * h * uy
    ax, ay = x0 - ccx, y0 - ccy
    bx, by = x1 - ccx, y1 - ccy
    a0, a1 = math.atan2(ay, ax), math.atan2(by, bx)
    da = a1 - a0
    while da <= -math.pi:
        da += 2 * math.pi
    while da > math.pi:
        da -= 2 * math.pi
    if laf:
        da = da - math.copysign(2 * math.pi, da)
    am = a0 + da / 2.0
    return (ccx + r * math.cos(am), ccy + r * math.sin(am))


# ---------------------------------------------------------------- parsing

class Pin:
    __slots__ = ('etype', 'hidden', 'x', 'y', 'length', 'dx', 'dy',
                 'name', 'number', 'name_vis', 'num_vis')


class Component:
    pass


def split_attrs(s):
    """`key`value`key`value` ... -> dict"""
    f = s.split('`')
    return {f[i]: f[i + 1] for i in range(0, len(f) - 1, 2) if f[i]}


def parse_component(raw):
    parts = raw.split('#@$')
    h = parts[0].split('~')
    c = Component()
    c.x, c.y = num(h[1]), num(h[2])
    c.attrs = split_attrs(h[3])
    c.rot = int(num(h[4]))
    c.gge = h[6] if len(h) > 6 else ''
    c.name = c.prefix = ''
    c.name_at = c.prefix_at = None
    c.name_vis = c.prefix_vis = True
    c.pins, c.gfx, c.texts = [], [], []

    for p in parts[1:]:
        f = p.split('~')
        t = f[0]
        if t == 'T' and f[1] in ('N', 'P'):
            if f[1] == 'N':
                c.name, c.name_at = f[12], (num(f[2]), num(f[3]))
                c.name_vis = f[13] != '0'
            else:
                c.prefix, c.prefix_at = f[12], (num(f[2]), num(f[3]))
                c.prefix_vis = f[13] != '0'
        elif t == 'T':
            c.texts.append(dict(x=num(f[2]), y=num(f[3]), rot=num(f[4]),
                                size=num(re.sub(r'[^\d.]', '', f[7]), 7) or 7,
                                text=f[12], vis=f[13] != '0', anchor=f[14]))
        elif t == 'P':
            s = p.split('^^')
            hd = s[0].split('~')
            pin = Pin()
            pin.etype = hd[2]
            pin.hidden = (hd[1] == 'none')
            pin.x, pin.y = num(hd[4]), num(hd[5])
            m = re.match(r'\s*M\s*(-?[\d.]+)[ ,]+(-?[\d.]+)\s*([hv])\s*(-?[\d.]+)',
                         s[2].split('~')[0])
            if m:
                pin.length = abs(num(m.group(4)))
                if m.group(3) == 'h':
                    pin.dx, pin.dy = math.copysign(1, num(m.group(4))), 0.0
                else:
                    pin.dx, pin.dy = 0.0, math.copysign(1, num(m.group(4)))
            else:
                pin.length, pin.dx, pin.dy = 10.0, -1.0, 0.0
            nm = s[3].split('~') if len(s) > 3 else []
            nu = s[4].split('~') if len(s) > 4 else []
            pin.name = nm[4] if len(nm) > 4 else ''
            pin.name_vis = bool(nm) and nm[0] != '0'
            pin.number = nu[4] if len(nu) > 4 else ''
            pin.num_vis = bool(nu) and nu[0] != '0'
            if not pin.number:
                pin.number = hd[3]
            if not pin.name:
                pin.name = pin.number
            c.pins.append(pin)
        else:
            c.gfx.append(p)
    return c


# ------------------------------------------------------- symbol generation

def gfx_to_sexp(frame, raw, indent):
    """Convert one EasyEDA graphic primitive to KiCad symbol graphics."""
    f = raw.split('~')
    t = f[0]
    o, pad = [], '\t' * indent

    def stroke_fill(fill):
        if fill in ('', '0', 'none', 'transparent'):
            kind = 'none'
        elif fill.upper() in ('#FFFFFF', '#FFF'):
            kind = 'background'       # EasyEDA paints inversion bubbles white
        else:
            kind = 'outline'
        return ('%s\t(stroke (width 0) (type default))\n%s\t(fill (type %s))'
                % (pad, pad, kind))

    def poly(points, fill=''):
        if len(points) < 2:
            return
        pts = ' '.join('(xy %s %s)' % (fmt(a), fmt(b)) for a, b in points)
        o.append('%s(polyline\n%s\t(pts %s)\n%s\n%s)'
                 % (pad, pad, pts, stroke_fill(fill), pad))

    if t == 'R':
        x, y, w, h = num(f[1]), num(f[2]), num(f[5]), num(f[6])
        p1, p2 = frame.pt(x, y), frame.pt(x + w, y + h)
        o.append('%s(rectangle\n%s\t(start %s %s)\n%s\t(end %s %s)\n%s\n%s)'
                 % (pad, pad, fmt(min(p1[0], p2[0])), fmt(min(p1[1], p2[1])),
                    pad, fmt(max(p1[0], p2[0])), fmt(max(p1[1], p2[1])),
                    stroke_fill(f[10]), pad))
    elif t == 'E':
        cx, cy, rx, ry = num(f[1]), num(f[2]), num(f[3]), num(f[4])
        c = frame.pt(cx, cy)
        if abs(rx - ry) < 1e-6:
            o.append('%s(circle\n%s\t(center %s %s)\n%s\t(radius %s)\n%s\n%s)'
                     % (pad, pad, fmt(c[0]), fmt(c[1]), pad, fmt(rx * U),
                        stroke_fill(f[8]), pad))
        else:
            pts = []
            for k in range(33):
                a = 2 * math.pi * k / 32.0
                pts.append(frame.pt(cx + rx * math.cos(a), cy + ry * math.sin(a)))
            poly(pts, f[8])
    elif t in ('PL', 'PG'):
        v = [num(s) for s in f[1].replace(',', ' ').split()]
        pts = [frame.pt(v[i], v[i + 1]) for i in range(0, len(v) - 1, 2)]
        if t == 'PG' and pts:
            pts.append(pts[0])
        poly(pts, f[5] if len(f) > 5 else '')   # f[4] is the dash style
    elif t in ('PT', 'A'):
        fill = f[5] if len(f) > 5 else ''
        for seg in parse_path(f[1]):
            if seg[0] == 'poly':
                poly([frame.pt(x, y) for x, y in seg[1]], fill)
            else:
                _, p0, prm, p1 = seg
                pm = arc_mid(p0, prm, p1)
                a, b, cpt = frame.pt(*p0), frame.pt(*pm), frame.pt(*p1)
                o.append('%s(arc\n%s\t(start %s %s)\n%s\t(mid %s %s)\n'
                         '%s\t(end %s %s)\n%s\n%s)'
                         % (pad, pad, fmt(a[0]), fmt(a[1]), pad, fmt(b[0]),
                            fmt(b[1]), pad, fmt(cpt[0]), fmt(cpt[1]),
                            stroke_fill(''), pad))
    return o


def body_box(frame, gfx):
    """Bounds of the largest rectangle in a symbol -- its body outline."""
    best = None
    for g in gfx:
        f = g.split('~')
        if f[0] != 'R':
            continue
        x, y, w, h = num(f[1]), num(f[2]), num(f[5]), num(f[6])
        p1, p2 = frame.pt(x, y), frame.pt(x + w, y + h)
        box = (min(p1[0], p2[0]), min(p1[1], p2[1]),
               max(p1[0], p2[0]), max(p1[1], p2[1]))
        area = (box[2] - box[0]) * (box[3] - box[1])
        if best is None or area > best[0]:
            best = (area, box)
    return best[1] if best else None


def symbol_body(comp, unit, name, indent=2):
    """Emit `(symbol "<name>_<unit>_1" ...)` for one unit of a symbol."""
    frame = Frame(comp.x, comp.y, comp.rot)
    pad = '\t' * indent
    o = ['%s(symbol %s' % (pad, q('%s_%d_1' % (name, unit)))]

    # --- ANSI distinctive shape, drawn into the box the GOST rectangle used,
    #     so that every pin stays exactly where it is and no wire has to move.
    kind = _US[0].gate_kind(comp.name) if (_US[0] and _ANSI[0]) else None
    box = body_box(frame, comp.gfx) if kind else None
    reach = {}
    if kind and box:
        import ansi_symbols
        ins = [p for p in comp.pins
               if not p.hidden and frame.angle(p.dx, p.dy) == 0]
        outs = [p for p in comp.pins
                if not p.hidden and frame.angle(p.dx, p.dy) == 180]
        if len(outs) == 1 and ins:
            left, right = box[0], box[2]
            cy = frame.pt(outs[0].x, outs[0].y)[1]
            half_h = (box[3] - box[1]) / 2.0
            if kind in ('not', 'buf'):
                half_h = min(half_h, 2.54)
            o.extend(ansi_symbols.gate_body(kind, left, right, cy, half_h,
                                            indent + 1))
            for p in ins:
                px, py = frame.pt(p.x, p.y)
                reach[id(p)] = abs(ansi_symbols.input_reach(
                    kind, left, cy, half_h, py) - px)
        else:
            kind = None

    if not kind:
        for g in comp.gfx:
            o.extend(gfx_to_sexp(frame, g, indent + 1))

    for tx in comp.texts:
        if not tx['vis'] or not tx['text']:
            continue
        if kind:
            continue                      # the shape replaces the qualifier
        if _US[0] and _ANSI[0]:
            lbl = _US[0].box_label(tx['text'])
            if lbl is not None:
                # A body too narrow to hold the label would have it collide
                # with the pin names; the part number below identifies it
                # anyway, so drop it there.
                bb = body_box(frame, comp.gfx)
                if not lbl or (bb and (bb[2] - bb[0]) < 11.0):
                    continue
                tx = dict(tx, text=lbl)
        x, y = frame.pt(tx['x'], tx['y'])
        size = max(tx['size'] * PT, 0.5)
        ang = (frame.angle(1, 0)) % 180
        o.append('%s\t(text %s\n%s\t\t(at %s %s %d)\n'
                 '%s\t\t(effects (font (size %s %s))%s)\n%s\t)'
                 % (pad, q(tx['text']), pad, fmt(x), fmt(y), ang,
                    pad, fmt(size), fmt(size), justify(tx['anchor']), pad))

    for pin in comp.pins:
        px, py = frame.pt(pin.x, pin.y)
        ang = frame.angle(pin.dx, pin.dy)
        pin_len = reach.get(id(pin), pin.length * U)
        pin_name = pin.name
        if _US[0] and _ANSI[0] and not pin.hidden:
            # a distinctive-shape gate carries no pin names in US practice
            pin_name = '~' if kind else _US[0].pin_name(
                comp.name, pin.number, pin.name)
        if pin.hidden:
            # A hidden pin is invisible in EasyEDA and connects by name only,
            # so its nominal coordinates are arbitrary -- and several of them
            # happen to land on a wire or another pin. KiCad *would* connect
            # those geometrically (shorting VCC to GND here), so nudge them
            # half a grid step off the 1.27 mm connection grid.
            py += 0.635
        # EasyEDA hides a pin (always VCC/GND here) precisely so that it is
        # connected by name; KiCad does that for invisible power-input pins.
        etype = 'power_in' if pin.hidden else ETYPE.get(pin.etype, 'passive')
        o.append(
            '%s\t(pin %s line\n'
            '%s\t\t(at %s %s %d)\n'
            '%s\t\t(length %s)%s\n'
            '%s\t\t(name %s (effects (font (size 1.27 1.27))))\n'
            '%s\t\t(number %s (effects (font (size 1.27 1.27))))\n'
            '%s\t)'
            % (pad, etype,
               pad, fmt(px), fmt(py), ang,
               pad, fmt(pin_len), '\n%s\t\t(hide yes)' % pad if pin.hidden else '',
               pad, q(pin_name), pad, q(pin.number), pad))
    o.append('%s)' % pad)
    return o


def sheet_wire(p1, p2, uu):
    return ('\t(wire (pts (xy %s %s) (xy %s %s))\n'
            '\t\t(stroke (width 0) (type default))\n\t\t(uuid %s)\n\t)'
            % (fmt(p1[0]), fmt(p1[1]), fmt(p2[0]), fmt(p2[1]), q(uu)))


def sheet_line(p1, p2, uu):
    """A purely graphical line.

    EasyEDA buses and bus entries carry no connectivity of their own here --
    every wire leaving a bus is named by a net label -- while a KiCad bus
    would merge all of those nets into one.  They are therefore drawn as
    graphics so the picture is kept and the netlist stays correct.
    """
    return ('\t(polyline (pts (xy %s %s) (xy %s %s))\n'
            '\t\t(stroke (width 0.381) (type solid) (color 0 132 0 1))\n'
            '\t\t(uuid %s)\n\t)'
            % (fmt(p1[0]), fmt(p1[1]), fmt(p2[0]), fmt(p2[1]), q(uu)))


def justify(anchor, vertical='bottom'):
    """EasyEDA text anchor -> KiCad justify clause ("center" is the default)."""
    h = {'start': 'left', 'end': 'right'}.get(anchor, '')
    parts = [p for p in (h, vertical) if p]
    return ' (justify %s)' % ' '.join(parts) if parts else ''


def prop(key, value, x, y, ang=0, size=DEF_TEXT, hide=False, just=None,
         indent=2):
    pad = '\t' * indent
    eff = ['(font (size %s %s))' % (fmt(size), fmt(size))]
    if just:
        eff.append('(justify %s)' % just)
    if hide:
        eff.append('(hide yes)')
    return ('%s(property %s %s\n%s\t(at %s %s %d)\n%s\t(effects %s)\n%s)'
            % (pad, q(key), q(value), pad, fmt(x), fmt(y), ang,
               pad, ' '.join(eff), pad))


# ---------------------------------------------------------------- main

def convert(src, outdir, project, us=False, ansi=False):
    import os
    doc = json.load(open(src, encoding='utf-8'))
    sheet = doc['schematics'][0]['dataStr']
    shapes = sheet['shape']

    if us:
        import us_parts
        _FP[0] = us_parts
        _US[0] = us_parts
        _ANSI[0] = ansi

    comps = [parse_component(s) for s in shapes if s.startswith('LIB~')]

    # --- the drawing frame is a pin-less "component"; use it for the title block
    frames = [c for c in comps if not c.pins]
    comps = [c for c in comps if c.pins]
    title_block = {'title': doc.get('title', project), 'rev': '', 'date': '',
                   'company': '', 'comment': ''}
    # frame texts carry a trailing category tag (frame_title / frame_version ...)
    for s in shapes:
        if not s.startswith('LIB~'):
            continue
        for p in s.split('#@$')[1:]:
            f = p.split('~')
            if f[0] != 'T' or len(f) < 18:
                continue
            tag, text = f[17], f[12]
            if tag == 'frame_title':
                title_block['title'] = text
            elif tag == 'frame_version':
                title_block['rev'] = text
            elif tag == 'frame_date':
                title_block['date'] = text
            elif tag == 'frame_company':
                title_block['company'] = text
            elif tag == 'frame_drawn':
                title_block['comment'] = 'Drawn by: ' + text

    # -------------------------------------------- Western part substitution
    subs = {}
    if us:
        import us_parts
        for c in comps:
            new_value = us_parts.western(c.name)
            if new_value:
                subs.setdefault(c.name, new_value)
                c.orig_name = c.name
                c.description = us_parts.description(c.name)
                c.name = new_value
            else:
                c.orig_name = ''
                c.description = ''
    else:
        for c in comps:
            c.orig_name = ''
            c.description = ''

    # ------------------------------------------------ group units into parts
    for c in comps:
        m = re.match(r"^(.*?)(?:\.(\d+))?$", c.prefix)
        c.base = m.group(1) or c.prefix
        c.unit = int(m.group(2)) if m.group(2) else 1
        c.ghash = unit_hash(c)

    parts = defaultdict(list)                 # base refdes -> [component, ...]
    for c in comps:
        parts[c.base].append(c)

    # Parts drawn the same way share one library symbol.  A part that only
    # uses some of a chip's gates still merges with a part that uses more of
    # them, as long as no unit disagrees about how it is drawn.
    variants = defaultdict(list)          # group name -> [ {unit: component} ]
    for base in sorted(parts):
        units = sorted(parts[base], key=lambda c: c.unit)
        gname = group_name(units[0])
        for var in variants[gname]:
            if all(u.unit not in var or var[u.unit].ghash == u.ghash for u in units):
                for u in units:
                    var.setdefault(u.unit, u)
                target = var
                break
        else:
            target = {u.unit: u for u in units}
            variants[gname].append(target)
        for c in units:
            c.variant = (gname, id(target))

    symbols, var_name = OrderedDict(), {}
    for gname, vars_ in variants.items():
        for i, var in enumerate(vars_):
            sname = gname if i == 0 else '%s_%d' % (gname, i + 1)
            var_name[(gname, id(var))] = sname
            symbols[sname] = [var[u] for u in sorted(var)]
    for c in comps:
        c.symbol = var_name[c.variant]

    # ------------------------------------------------ coordinate transform
    bb = sheet.get('BBox', {})
    # EasyEDA connection points sit on a 5-unit (1.27 mm) grid; keep the
    # origin on that grid too, otherwise every wire and pin lands off-grid
    # in KiCad and nothing connects.
    minx = math.floor(num(bb.get('x', 0)) / 5.0) * 5
    miny = math.floor(num(bb.get('y', 0)) / 5.0) * 5
    w_mm = (num(bb.get('x', 0)) + num(bb.get('width', 0)) - minx) * U
    h_mm = (num(bb.get('y', 0)) + num(bb.get('height', 0)) - miny) * U
    page_w = math.ceil((w_mm + 40) / 10.0) * 10
    page_h = math.ceil((h_mm + 40) / 10.0) * 10
    # keep the 1.27 mm grid: offsets are whole multiples of 5 EasyEDA units
    off_x = round(((page_w - w_mm) / 2.0) / (5 * U)) * 5 * U
    off_y = round(((page_h - h_mm) / 2.0) / (5 * U)) * 5 * U

    def X(v):
        return (num(v) - minx) * U + off_x

    def Y(v):
        return (num(v) - miny) * U + off_y

    # ------------------------------------------------ build the symbol library
    lib = ['(kicad_symbol_lib', '\t(version 20250114)',
           '\t(generator "easyeda_sch_to_kicad")', '\t(generator_version "1.0")']
    lib.extend(gnd_symbol())
    for sname, units in symbols.items():
        lib.extend(symbol_def(sname, units))
    lib.append(')')
    lib_txt = '\n'.join(lib) + '\n'

    # ------------------------------------------------ build the schematic
    root = uid(project, 'root')
    out = ['(kicad_sch', '\t(version 20250114)',
           '\t(generator "easyeda_sch_to_kicad")', '\t(generator_version "1.0")',
           '\t(uuid %s)' % q(root),
           '\t(paper "User" %s %s)' % (fmt(page_w), fmt(page_h)),
           '\t(title_block',
           '\t\t(title %s)' % q(title_block['title']),
           '\t\t(date %s)' % q(title_block['date']),
           '\t\t(rev %s)' % q(title_block['rev']),
           '\t\t(company %s)' % q(title_block['company']),
           '\t\t(comment 1 %s)' % q(title_block['comment']),
           '\t\t(comment 2 "Converted from EasyEDA source by easyeda_sch_to_kicad.py")',
           '\t)',
           '\t(lib_symbols']
    # The library is embedded in the schematic, where each symbol is keyed by
    # its full "library:name" id -- the plain name used inside a .kicad_sym
    # would leave every placement unresolved.
    body = lib_txt.split('\n')[4:-2]
    for l in body:
        if l.startswith('\t(symbol "'):
            l = '\t(symbol "%s:%s' % (project, l.split('"', 1)[1])
        out.append('\t' + l if l else l)
    out.append('\t)')

    n_wire = n_bus = n_be = n_j = n_lab = n_nc = n_txt = 0
    for s in shapes:
        t = s.split('~')[0]
        f = s.split('~')
        if t == 'W' or t == 'B':
            v = [num(k) for k in f[1].split()]
            for i in range(0, len(v) - 3, 2):
                p1 = (X(v[i]), Y(v[i + 1]))
                p2 = (X(v[i + 2]), Y(v[i + 3]))
                uu = uid(f[6] if len(f) > 6 else s, i)
                if t == 'W':
                    out.append(sheet_wire(p1, p2, uu))
                    n_wire += 1
                else:
                    out.append(sheet_line(p1, p2, uu))
                    n_bus += 1
        elif t == 'BE':
            p1 = (X(f[2]), Y(f[3]))
            p2 = (X(f[4]), Y(f[5]))
            out.append(sheet_line(p1, p2, uid(f[6])))
            n_be += 1
        elif t == 'J':
            out.append('\t(junction (at %s %s) (diameter 0) (color 0 0 0 0)\n'
                       '\t\t(uuid %s)\n\t)'
                       % (fmt(X(f[1])), fmt(Y(f[2])), q(uid(f[5]))))
            n_j += 1
        elif t == 'O':
            out.append('\t(no_connect (at %s %s) (uuid %s))'
                       % (fmt(X(f[1])), fmt(Y(f[2])), q(uid(f[3]))))
            n_nc += 1
        elif t == 'N':
            size = max((num(re.sub(r'[^\d.]', '', f[11]), 7) or 7) * PT, 0.6)
            out.append('\t(label %s\n\t\t(at %s %s %d)\n'
                       '\t\t(effects (font (size %s %s))%s)\n'
                       '\t\t(uuid %s)\n\t)'
                       % (q(f[5]), fmt(X(f[1])), fmt(Y(f[2])),
                          (-int(num(f[3]))) % 360, fmt(size), fmt(size),
                          justify(f[7]), q(uid(f[6]))))
            n_lab += 1
        elif t == 'T':
            size = max((num(re.sub(r'[^\d.]', '', f[7]), 7) or 7) * PT, 0.6)
            out.append('\t(text %s\n\t\t(exclude_from_sim no)\n\t\t(at %s %s %d)\n'
                       '\t\t(effects (font (size %s %s))%s)\n'
                       '\t\t(uuid %s)\n\t)'
                       % (q(f[12]), fmt(X(f[2])), fmt(Y(f[3])),
                          (-int(num(f[4]))) % 360, fmt(size), fmt(size),
                          justify(f[14]), q(uid(f[15]))))
            n_txt += 1
        elif t == 'F':
            out.extend(netflag(s, X, Y, project, root))

    # ------------------------------------------------ symbol instances
    for base in sorted(parts):
        for c in sorted(parts[base], key=lambda k: k.unit):
            out.extend(instance(c, project, X, Y, root))

    out.append('\t(sheet_instances\n\t\t(path "/" (page "1"))\n\t)')
    out.append(')')

    os.makedirs(outdir, exist_ok=True)
    sch = os.path.join(outdir, project + '.kicad_sch')
    sym = os.path.join(outdir, project + '.kicad_sym')
    open(sch, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    open(sym, 'w', encoding='utf-8').write(lib_txt)
    open(os.path.join(outdir, 'sym-lib-table'), 'w', encoding='utf-8').write(
        '(sym_lib_table\n  (version 7)\n'
        '  (lib (name "%s")(type "KiCad")(uri "${KIPRJMOD}/%s.kicad_sym")'
        '(options "")(descr "Converted from EasyEDA"))\n)\n' % (project, project))
    open(os.path.join(outdir, project + '.kicad_pro'), 'w', encoding='utf-8').write(
        json.dumps({"board": {}, "boards": [], "libraries": {"pinned_footprint_libs": [],
                    "pinned_symbol_libs": []}, "meta": {"filename": project + ".kicad_pro",
                    "version": 1}, "net_settings": {}, "pcbnew": {},
                    "schematic": {}, "sheets": [[root, "Root"]], "text_variables": {}},
                   indent=2))

    if us:
        print('substituted: %d Soviet part numbers -> Western equivalents'
              % len(subs))
        for k in sorted(subs):
            print('   %-11s -> %s' % (k, subs[k]))
        nofp = sorted({c.attrs.get('package', '') for c in comps
                       if c.attrs.get('package') and not easyeda_fp(c)})
        if nofp:
            print('no footprint: %s' % ', '.join(nofp))
    print('symbols   : %d library symbols (%d placed parts, %d units)'
          % (len(symbols) + 1, len(parts), len(comps)))
    print('wires %d  bus graphics %d  bus-entry graphics %d  junctions %d'
          % (n_wire, n_bus, n_be, n_j))
    print('labels %d  no-connects %d  texts %d' % (n_lab, n_nc, n_txt))
    print('page      : User %s x %s mm' % (fmt(page_w), fmt(page_h)))
    print('written   : %s' % sch)
    return sch


def unit_hash(c):
    """Rotation-independent fingerprint of one drawn unit.

    Everything is expressed in library-local coordinates so that the same
    drawing placed at different sheet positions and rotations collapses onto
    a single library symbol.
    """
    import hashlib
    frame = Frame(c.x, c.y, c.rot)
    items = []
    for p in c.pins:
        x, y = frame.pt(p.x, p.y)
        items.append(('P', p.etype, p.hidden, round(x, 3), round(y, 3),
                      frame.angle(p.dx, p.dy), round(p.length, 2), p.name, p.number))
    for g in c.gfx:
        items.append(('G',) + tuple(gfx_to_sexp(frame, g, 0)))
    for t in c.texts:
        if t['vis'] and t['text']:
            x, y = frame.pt(t['x'], t['y'])
            items.append(('T', round(x, 3), round(y, 3), t['size'], t['text']))
    items.sort(key=lambda k: repr(k))
    return hashlib.md5(repr(items).encode()).hexdigest()[:12]


VALUE_RE = re.compile(r'^[0-9][0-9.]*\s*[a-zA-Zµ\u03bc%]{0,4}$')


def group_name(c):
    """Library symbol name: the part name, or the refdes prefix for passives."""
    name = c.name.strip()
    # A substituted Western part number is a part name by construction, even
    # when it looks like a value ("4164", "8255A").
    if name and getattr(c, 'orig_name', ''):
        return re.sub(r'[\s/:\\{}()"]+', '_', name).strip('_')
    if not name or VALUE_RE.match(name):
        name = re.match(r"^[A-Za-z#]*", c.base).group(0) or 'SYM'
    return re.sub(r'[\s/:\\{}()"]+', '_', name).strip('_') or 'SYM'


def symbol_def(sname, units):
    ref = re.match(r"^[A-Za-z#]*", units[0].base).group(0) or 'U'
    proto = units[0]
    frame = Frame(proto.x, proto.y, proto.rot)
    rx, ry = frame.pt(*(proto.prefix_at or (proto.x, proto.y - 20)))
    vx, vy = frame.pt(*(proto.name_at or (proto.x, proto.y - 10)))
    o = ['\t(symbol %s' % q(sname),
         '\t\t(pin_names (offset 0.508))',
         '\t\t(exclude_from_sim no)', '\t\t(in_bom yes)', '\t\t(on_board yes)',
         prop('Reference', ref, rx, ry),
         prop('Value', proto.name or sname, vx, vy),
         prop('Footprint', easyeda_fp(proto), 0, 0, hide=True),
         prop('Datasheet', '', 0, 0, hide=True),
         prop('Description', getattr(proto, 'description', '') or proto.name,
              0, 0, hide=True)]
    for u in units:
        o.extend(symbol_body(u, u.unit, sname))
    o.append('\t)')
    return o


_FP = [None]
_US = [None]      # us_parts module, set in --us mode
_ANSI = [False]   # draw ANSI distinctive-shape gates


def easyeda_fp(c):
    """KiCad footprint link.

    EasyEDA package names do not exist in any KiCad footprint library, so the
    field is normally left empty (a dangling link breaks the netlist-to-board
    flow) and the original name is kept in the EasyEDA_Package property.
    In --us mode a real KiCad footprint is assigned where the package maps
    unambiguously.
    """
    if _FP[0] is None:
        return ''
    return _FP[0].footprint(c.attrs.get('package', ''))


def gnd_symbol():
    return [
        '\t(symbol "GND"',
        '\t\t(power)', '\t\t(pin_numbers (hide yes))',
        '\t\t(pin_names (offset 0) (hide yes))',
        '\t\t(exclude_from_sim no)', '\t\t(in_bom no)', '\t\t(on_board yes)',
        prop('Reference', '#PWR', 0, 1.27, hide=True),
        prop('Value', 'GND', 0, -3.81),
        prop('Footprint', '', 0, 0, hide=True),
        prop('Datasheet', '', 0, 0, hide=True),
        '\t\t(symbol "GND_0_1"',
        '\t\t\t(polyline (pts (xy 0 0) (xy 0 -2.54)) (stroke (width 0) (type default)) (fill (type none)))',
        '\t\t\t(polyline (pts (xy -2.286 -2.54) (xy 2.286 -2.54)) (stroke (width 0) (type default)) (fill (type none)))',
        '\t\t\t(polyline (pts (xy -1.524 -3.048) (xy 1.524 -3.048)) (stroke (width 0) (type default)) (fill (type none)))',
        '\t\t\t(polyline (pts (xy -0.762 -3.556) (xy 0.762 -3.556)) (stroke (width 0) (type default)) (fill (type none)))',
        '\t\t\t(polyline (pts (xy -0.254 -4.064) (xy 0.254 -4.064)) (stroke (width 0) (type default)) (fill (type none)))',
        '\t\t)',
        '\t\t(symbol "GND_1_1"',
        '\t\t\t(pin power_in line (at 0 0 90) (length 0) (hide yes)',
        '\t\t\t\t(name "GND" (effects (font (size 1.27 1.27))))',
        '\t\t\t\t(number "1" (effects (font (size 1.27 1.27))))',
        '\t\t\t)',
        '\t\t)',
        '\t)',
    ]


_pwr_n = [0]


def netflag(raw, X, Y, project, root):
    """EasyEDA net flag: GND symbol or net port (-> KiCad global label)."""
    parts = raw.split('^^')
    h = parts[0].split('~')
    kind, rot, gge = h[1], int(num(h[4])), h[5]
    px, py = [num(v) for v in parts[1].split('~')]
    spec = parts[2].split('~')
    net = spec[0]
    if kind == 'part_netLabel_gnD':
        _pwr_n[0] += 1
        ref = '#PWR%02d' % _pwr_n[0]
        u = uid(gge)
        return ['\t(symbol',
                '\t\t(lib_id "%s:GND")' % project,
                '\t\t(at %s %s %d)' % (fmt(X(px)), fmt(Y(py)), rot % 360),
                '\t\t(unit 1)',
                '\t\t(exclude_from_sim no) (in_bom no) (on_board yes) (dnp no)',
                '\t\t(uuid %s)' % q(u),
                prop('Reference', ref, X(px), Y(py) + 1.27, hide=True, indent=2),
                prop('Value', 'GND', X(px), Y(py) + 4.4, indent=2),
                '\t\t(pin "1" (uuid %s))' % q(uid(gge, 'p1')),
                '\t\t(instances (project %s (path "/%s" (reference %s) (unit 1))))'
                % (q(project), root, q(ref)),
                '\t)']
    raw_size = re.sub(r'[^\d.]', '', spec[7] if len(spec) > 7 else '')
    size = max((num(raw_size, 8) or 8) * PT, 0.8)
    return ['\t(global_label %s' % q(net),
            '\t\t(shape bidirectional)',
            '\t\t(at %s %s %d)' % (fmt(X(px)), fmt(Y(py)), (-rot) % 360),
            '\t\t(effects (font (size %s %s)) (justify left))' % (fmt(size), fmt(size)),
            '\t\t(uuid %s)' % q(uid(gge)),
            '\t)']


def instance(c, project, X, Y, root):
    u = uid(c.gge)
    px, py = c.prefix_at or (c.x, c.y - 20)
    nx, ny = c.name_at or (c.x, c.y - 10)
    o = ['\t(symbol',
         '\t\t(lib_id "%s:%s")' % (project, c.symbol),
         '\t\t(at %s %s %d)' % (fmt(X(c.x)), fmt(Y(c.y)), c.rot % 360),
         '\t\t(unit %d)' % c.unit,
         '\t\t(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)',
         '\t\t(uuid %s)' % q(u),
         prop('Reference', c.base, X(px), Y(py), indent=2, just='left',
              hide=not c.prefix_vis),
         prop('Value', c.name, X(nx), Y(ny), indent=2, just='left',
              hide=not c.name_vis),
         prop('Footprint', easyeda_fp(c), X(c.x), Y(c.y), hide=True, indent=2),
         prop('Datasheet', '', X(c.x), Y(c.y), hide=True, indent=2)]
    extra = OrderedDict()
    a = c.attrs
    for src, dst in (('Manufacturer', 'Manufacturer'),
                     ('BOM_Manufacturer', 'Manufacturer'),
                     ('Manufacturer Part', 'MPN'),
                     ('BOM_Manufacturer Part', 'MPN'),
                     ('Supplier Part', 'LCSC'),
                     ('BOM_Supplier Part', 'LCSC')):
        if a.get(src):
            extra.setdefault(dst, a[src])
    if a.get('package'):
        extra['EasyEDA_Package'] = a['package']
    if c.unit != 1 or '.' in c.prefix:
        extra['EasyEDA_Ref'] = c.prefix
    if getattr(c, 'orig_name', ''):
        extra['Original_Part'] = c.orig_name
    for k, v in extra.items():
        o.append(prop(k, v, X(c.x), Y(c.y), hide=True, indent=2))
    for i, p in enumerate(c.pins):
        o.append('\t\t(pin %s (uuid %s))' % (q(p.number), q(uid(c.gge, 'p', i))))
    o.append('\t\t(instances (project %s (path "/%s" (reference %s) (unit %d))))'
             % (q(project), root, q(c.base), c.unit))
    o.append('\t)')
    return o


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    convert(args[0], args[1],
            args[2] if len(args) > 2 else 'converted',
            us='--us' in sys.argv or '--ansi' in sys.argv,
            ansi='--ansi' in sys.argv)
