#!/usr/bin/env python3
"""ANSI/IEEE distinctive-shape gate bodies for KiCad symbol libraries.

The point of this module is that the shapes are drawn *into the box the
original rectangular (GOST) body occupied*, and the pins are not moved. That
keeps a converted schematic's wiring exactly as it was while turning the
rectangles-with-a-qualifier into the AND/OR/XOR shapes a US schematic uses.

Everything here is in KiCad symbol-library coordinates (millimetres, Y up).
"""

import math

BUBBLE_R = 0.635          # inversion bubble radius
OR_BACK = 0.35            # back-curve bulge, as a fraction of the half-height
XOR_GAP = 0.762           # spacing between the two XOR back curves

STROKE = '(stroke (width 0) (type default)) (fill (type none))'


def _poly(pts, pad):
    s = ' '.join('(xy %s %s)' % (_f(x), _f(y)) for x, y in pts)
    return '%s(polyline (pts %s) %s)' % (pad, s, STROKE)


def _arc(a, m, b, pad):
    return ('%s(arc (start %s %s) (mid %s %s) (end %s %s) %s)'
            % (pad, _f(a[0]), _f(a[1]), _f(m[0]), _f(m[1]),
               _f(b[0]), _f(b[1]), STROKE))


def _circle(c, r, pad):
    return ('%s(circle (center %s %s) (radius %s) %s)'
            % (pad, _f(c[0]), _f(c[1]), _f(r), STROKE))


def _f(v):
    v = round(v + 0.0, 4)
    if v == 0:
        v = 0.0
    return ('%.4f' % v).rstrip('0').rstrip('.') or '0'


def back_arc_x(left, half_h, y, cy):
    """x of the OR-family back curve at height y.

    The curve passes through (left, cy±half_h) and bulges right to
    (left + b, cy); this returns where it sits at an arbitrary y, so that input
    pins can be lengthened to meet it instead of stopping short.
    """
    b = OR_BACK * half_h
    if b <= 0:
        return left
    r = (b * b + half_h * half_h) / (2 * b)
    xc = left + b - r
    dy = y - cy
    if abs(dy) > r:
        return left
    return xc + math.sqrt(r * r - dy * dy)


def gate_body(kind, left, right, cy, half_h, indent=3):
    """Graphics for one gate.

    kind   one of and/nand/or/nor/xor/xnor/not/buf
    left   x of the body's left edge (where the input pins arrive)
    right  x of the body's right edge (where the output pin leaves)
    cy     y of the output pin
    half_h half-height of the body box
    """
    pad = '\t' * indent
    inverting = kind in ('nand', 'nor', 'xnor', 'not')
    tip = right - 2 * BUBBLE_R if inverting else right
    out = []

    if kind in ('and', 'nand'):
        cx = tip - half_h
        out.append(_poly([(cx, cy + half_h), (left, cy + half_h),
                          (left, cy - half_h), (cx, cy - half_h)], pad))
        out.append(_arc((cx, cy - half_h), (tip, cy), (cx, cy + half_h), pad))

    elif kind in ('or', 'nor', 'xor', 'xnor'):
        back = left + (XOR_GAP if kind in ('xor', 'xnor') else 0.0)
        b = OR_BACK * half_h
        # the two flanks, each an arc from the back corner to the tip
        for sgn in (+1, -1):
            mid = (back + 0.55 * (tip - back), cy + sgn * 0.70 * half_h)
            out.append(_arc((back, cy + sgn * half_h), mid, (tip, cy), pad))
        # the back curve, and for XOR a second one outside it
        out.append(_arc((back, cy - half_h), (back + b, cy),
                        (back, cy + half_h), pad))
        if kind in ('xor', 'xnor'):
            out.append(_arc((left, cy - half_h), (left + b, cy),
                            (left, cy + half_h), pad))

    elif kind in ('not', 'buf'):
        out.append(_poly([(left, cy + half_h), (tip, cy),
                          (left, cy - half_h), (left, cy + half_h)], pad))

    if inverting:
        out.append(_circle((right - BUBBLE_R, cy), BUBBLE_R, pad))
    return out


def input_reach(kind, left, cy, half_h, y):
    """x an input pin should extend to so that it meets the body outline."""
    if kind in ('or', 'nor'):
        return back_arc_x(left, half_h, y, cy)
    if kind in ('xor', 'xnor'):
        return back_arc_x(left, half_h, y, cy)   # outer curve starts at `left`
    return left
