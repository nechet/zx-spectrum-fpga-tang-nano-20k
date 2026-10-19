#!/usr/bin/env python3
"""Generate a structural Verilog netlist from the EasyEDA schematic source.

Every IC on the board becomes one module instance whose ports are its DIP pin
numbers (p1 … pN), so the wiring is a direct transcription of the netlist
produced by Tools/easyeda_netlist.py -- which is itself verified identical to
what KiCad extracts from the converted schematic.

Passives and the analogue sections cannot be transcribed and are handled by the
rules in PASSIVE HANDLING below; every one of them is reported on stderr and
summarised in Verilog/README.md.

Usage:  python3 easyeda_to_verilog.py <schematic.json> <out.v> [top_name]
"""

import glob
import os
import re
import sys
from collections import OrderedDict, defaultdict

from easyeda_netlist import load

# --------------------------------------------------------------- device table
# value in the schematic -> (verilog module, {output pins}, {inout pins})
DEVICES = {
    'Z80':        ('z80_chip',  set(range(30, 41)) | {1, 2, 3, 4, 5, 18, 19, 20,
                                                      21, 22, 23, 27, 28},
                                {7, 8, 9, 10, 12, 13, 14, 15}),
    'КР580ВВ55':  ('i8255',     set(),
                                {1, 2, 3, 4, 37, 38, 39, 40, 18, 19, 20, 21, 22,
                                 23, 24, 25, 10, 11, 12, 13, 14, 15, 16, 17,
                                 27, 28, 29, 30, 31, 32, 33, 34}),
    '27C128':     ('rom_27c128', {11, 12, 13, 15, 16, 17, 18, 19}, set()),
    'КР565РУ5Д':  ('dram_x1',   {14}, set()),
    'КР565РУ6Г':  ('dram_x1',   {14}, set()),
    'К555ЛА3':    ('ttl_7400',  {3, 6, 8, 11}, set()),
    'К555ЛЕ1':    ('ttl_7402',  {1, 4, 10, 13}, set()),
    'К555ЛН1':    ('ttl_7404',  {2, 4, 6, 8, 10, 12}, set()),
    'К555ЛИ1':    ('ttl_7408',  {3, 6, 8, 11}, set()),
    'К555ЛА4':    ('ttl_7410',  {12, 6, 8}, set()),
    'К555ЛЛ1':    ('ttl_7432',  {3, 6, 8, 11}, set()),
    'К555ЛП5':    ('ttl_7486',  {3, 6, 8, 11}, set()),
    'К555ТМ2':    ('ttl_7474',  {5, 6, 8, 9}, set()),
    'К555ТМ8':    ('ttl_74175', {2, 3, 6, 7, 10, 11, 14, 15}, set()),
    'К1533ИЕ7':   ('ttl_74193', {2, 3, 6, 7, 12, 13}, set()),
    'К1533ИД4':   ('ttl_74155', {4, 5, 6, 7, 9, 10, 11, 12}, set()),
    'К555КП2':    ('ttl_74153', {7, 9}, set()),
    'К555КП12':   ('ttl_74253', {7, 9}, set()),
    'КР555КП16':  ('ttl_74157', {4, 7, 9, 12}, set()),
    'К555КП11A':  ('ttl_74257', {4, 7, 9, 12}, set()),
    'К555КП14':   ('ttl_74258', {4, 7, 9, 12}, set()),
    'К555ИР16':   ('ttl_74295', {10, 11, 12, 13}, set()),
    'К555КП13':   ('ttl_74298', {12, 13, 14, 15}, set()),
    'К561ЛЕ5':    ('cd4001',    {3, 4, 10, 11}, set()),
    'К561ЛА7':    ('cd4011',    {3, 4, 10, 11}, set()),
    'К561ЛН2':    ('cd4069',    {2, 4, 6, 8, 10, 12}, set()),
    'К561ТМ2':    ('cd4013',    {1, 2, 12, 13}, set()),   # Q1 /Q1 /Q2 Q2 -- see cd4013
    'К561ИР2':    ('cd4015',    {2, 3, 4, 5, 10, 11, 12, 13}, set()),
    'К561ИЕ10':   ('cd4520',    {3, 4, 5, 6, 11, 12, 13, 14}, set()),
}

# 16K x 1 parts get a 7-bit row/column address
DRAM_ROWBITS = {'КР565РУ5Д': 8, 'КР565РУ6Г': 7}

POWER = ('VCC', 'GND')
SKIP_PARTS = {'D100'}         # unnamed spare DIP outline, no device fitted

# ------------------------------------------------------------------- overrides
# Hand-written exceptions, each replacing a piece of analogue circuitry that a
# structural netlist cannot express.  Keep this list short and explain each one.
#
# 1. The 14 MHz crystal oscillator (ZQ1 + R6 + R7 around D8 gates 1 and 2) is a
#    ring oscillator; it cannot run in a digital simulation.  D8 pin 4 is cut
#    loose and F14M is driven from the top-level clock input instead.
PIN_OVERRIDES = {('D8', '4'): 'osc_loop_open',   # gate 2 output, was F14M
                 ('D8', '1'): 'GND',            # gate 1 input, was the crystal
                 ('D63', '5'): 'N$160',         # see 3.: gate 3 input, was N$161
                 ('D63', '11'): 'N$162'}        #         gate 5 input, was N$164
DROP_PARTS = {'ZQ1', 'R6', 'R7',      # crystal oscillator network
              "R'", "C'", 'VD1',      # /INT differentiator, replaced below
              'C11', 'VD2', 'VD3', 'C13', 'C14', 'R34', 'R38', 'R42'}  # see 3.
#
# 2. C' + R' + VD1 differentiate the frame strobe -KSI into a /INT pulse.
#
# 3. The tape input (EAR) is analogue: D63 gate 1 with C11 and the diodes
#    VD2/VD3 is a limiting amplifier, gate 3 with R34/C14 a second one,
#    AC-coupled through C13, and gates 5 and 4 with R38/R42 a Schmitt trigger
#    giving TIN.  Without the capacitors the generator joined the leftovers
#    into nonsense: tape_in ended at a dead net, gate 3 had its output on its
#    own input, and gates 4/5 formed a latch with nothing to set it.  For a
#    logic-level input the chain is four inversions, so the overrides wire it
#    straight through -- gate 1 -> gate 3 -> gate 5 -> gate 4 -> TIN, which then
#    follows tape_in -- and drop the parts the overrides replace.
INT_PULSE = {'ksi_net': '-KSI', 'int_net': 'N$1', 'width_ns': 16500}

# Friendlier names for nets that become top-level ports
RENAME = {
    'N$5': 'res_n', 'N$23': 'jp_ru6',
    'N$2': 'nmi_n', 'N$3': 'wait_n', 'N$4': 'busrq_n',
    'N$149': 'vid_blue', 'N$150': 'vid_red', 'N$148': 'vid_green',
    'INTENSITY': 'vid_bright', '-SYNC': 'vid_sync_n',
    'N$157': 'tape_out', 'N$158': 'sound', 'N$159': 'tape_in',
    # The board's only sync output is composite: -SYNC is SSI xor ~-KSI, so
    # during the frame pulse the line sync is inverted rather than widened and
    # the usual pulse-width split does not work.  A scan doubler needs them
    # apart, so export the two internal syncs as well.
    'SSI': 'vid_hsync_n', '-KSI': 'vid_vsync_n',
}


def module_ports(libdir):
    """Read lib/*.v and return {module name: [port names in declaration order]}.

    The library is the authority on which pins a model actually has -- pin 1 of
    a 4164 is a no-connect, for instance -- so every instance can be emitted
    with all of its ports, and none invented.
    """
    out = {}
    for path in sorted(glob.glob(os.path.join(libdir, '*.v'))):
        src = re.sub(r'//[^\n]*', '', open(path, encoding='utf-8').read())
        for m in re.finditer(r'\bmodule\s+(\w+)\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;',
                             src, re.S):
            names, seen = [], set()
            for tok in re.finditer(r'\b(\w+)\b', m.group(2)):
                t = tok.group(1)
                if t in ('input', 'output', 'inout', 'wire', 'reg', 'signed'):
                    continue
                if t not in seen:
                    seen.add(t)
                    names.append(t)
            out[m.group(1)] = names
    return out


def inst_ident(ref):
    """Instance name for a refdes.

    Prefixed, because the data-bus nets are called D0…D7 while the chips are
    called D1…D66 -- without this they collide in the same scope.
    """
    return 'U_' + ident(ref)


def ident(name):
    """Turn a schematic net name into a legal Verilog identifier."""
    s = re.sub(r'[^A-Za-z0-9_]', '_', name)
    if not s or s[0].isdigit():
        s = 'n_' + s
    return s


def value_of(value_str):
    """'120pF' / '10k' / '1M' -> a float in base units."""
    m = re.match(r'^\s*([0-9.]+)\s*([a-zA-Zµ]*)', value_str or '')
    if not m:
        return None
    v = float(m.group(1))
    mult = {'': 1, 'R': 1, 'k': 1e3, 'K': 1e3, 'M': 1e6,
            'p': 1e-12, 'pF': 1e-12, 'n': 1e-9, 'nF': 1e-9,
            'u': 1e-6, 'uF': 1e-6, 'µF': 1e-6, 'mF': 1e-3}
    return v * mult.get(m.group(2), 1)


def convert(src, out_path, top='krasnodar48', libdir=None, synth=False):
    if libdir is None:
        libdir = os.path.join(os.path.dirname(os.path.abspath(out_path)), 'lib')
    modports = module_ports(libdir)
    if not modports:
        sys.exit('no chip models found in %s' % libdir)
    parts, nets = load(src)
    warn = lambda m: sys.stderr.write('  ' + m + '\n')

    ics, passives, connectors = OrderedDict(), OrderedDict(), OrderedDict()
    for ref, p in parts.items():
        if ref in SKIP_PARTS or ref in DROP_PARTS:
            continue
        if p.value in DEVICES:
            ics[ref] = p
        elif ref[0] in 'JX':
            connectors[ref] = p
        else:
            passives[ref] = p

    # ----------------------------------------------------- apply pin overrides
    for (ref, pin), newnet in PIN_OVERRIDES.items():
        if ref in ics:
            ics[ref].pins[pin] = newnet

    # ------------------------------------------------- which nets have drivers
    driven, ic_nets = set(), defaultdict(list)
    for ref, p in ics.items():
        _mod, outs, inouts = DEVICES[p.value]
        for pin, net in p.pins.items():
            ic_nets[net].append((ref, pin))
            if pin.isdigit() and (int(pin) in outs or int(pin) in inouts):
                driven.add(net)

    # ----------------------------------------------------------- PASSIVE RULES
    alias = {}            # net -> net it is merged into
    pulls, delays, dropped = [], [], []

    def resolve(n):
        while n in alias:
            n = alias[n]
        return n

    # capacitors, indexed by the net they decouple to a rail
    shunt_c = defaultdict(list)
    for ref, p in passives.items():
        if ref[0] != 'C':
            continue
        a, b = list(p.pins.values())[:2] if len(p.pins) >= 2 else (None, None)
        if a in POWER and b not in POWER:
            shunt_c[b].append((ref, value_of(p.value)))
        elif b in POWER and a not in POWER:
            shunt_c[a].append((ref, value_of(p.value)))

    for ref, p in sorted(passives.items()):
        if ref[0] == 'C':
            continue                                  # consumed above / decoupling
        if ref[0] == 'V':                             # diodes and the transistor
            dropped.append((ref, p.value, 'non-linear device'))
            continue
        if ref[0] != 'R':
            dropped.append((ref, p.value, 'unhandled part type'))
            continue
        ends = list(p.pins.values())
        if len(ends) != 2:
            dropped.append((ref, p.value, 'not a two-terminal net pair'))
            continue
        a, b = ends
        # 1. pull-up / pull-down to a rail
        if a in POWER or b in POWER:
            rail, sig = (a, b) if a in POWER else (b, a)
            if sig in ic_nets:
                pulls.append((ref, sig, rail))
            else:
                dropped.append((ref, p.value, 'ties %s to %s, no IC on it' % (sig, rail)))
            continue
        # 2. anything touching a net with no IC pin at all is analogue
        if a not in ic_nets or b not in ic_nets:
            dropped.append((ref, p.value, 'analogue node (%s / %s)' % (a, b)))
            continue
        # 3. series R with a shunt C on one side -> timing-correction delay
        src_net = dst_net = None
        if a in driven and b not in driven:
            src_net, dst_net = a, b
        elif b in driven and a not in driven:
            src_net, dst_net = b, a
        cval = None
        if dst_net and shunt_c.get(dst_net):
            cval = shunt_c[dst_net][0][1]
        if src_net and cval:
            tau_ps = 0.7 * value_of(p.value) * cval * 1e12
            delays.append((ref, src_net, dst_net, int(round(tau_ps))))
            continue
        # 4. plain series resistor: the two nets are one node
        if src_net:
            alias[dst_net] = src_net
        elif a in driven and b in driven:
            # A resistor between two driven nets is not a short -- it cannot
            # make two outputs one node.  R22 links D34's /Q2 to V3 through
            # 100k while D32 drives V3 directly, so D32 simply wins and the
            # other output loads it.  Merging the two would invent a second
            # driver on V3 and corrupt the vertical counter.
            dropped.append((ref, p.value,
                            'series link between two driven nets '
                            '(%s / %s), left separate' % (a, b)))
            continue
        else:
            alias[b] = a
        dropped.append((ref, p.value, 'series link, nets merged'))

    # ------------------------------------------------------------- port naming
    # Rebuild the maps over *resolved* net names: series resistors merged some
    # of them, and everything below classifies by what a net finally is.
    driven, sunk, bussed, ic_nets = set(), set(), set(), defaultdict(list)
    for ref, p in ics.items():
        _mod, outs, inouts = DEVICES[p.value]
        for pin, raw in p.pins.items():
            net = resolve(raw)
            ic_nets[net].append((ref, pin))
            n = int(pin) if pin.isdigit() else -1
            if n in inouts:
                driven.add(net)
                sunk.add(net)
                bussed.add(net)
            elif n in outs:
                driven.add(net)
            else:
                sunk.add(net)

    delay_dst = {resolve(d[2]) for d in delays}
    driven |= delay_dst
    sunk |= {resolve(d[1]) for d in delays}

    conn_nets = {resolve(n) for p in connectors.values() for n in p.pins.values()}

    used_nets = set(ic_nets) | delay_dst | {resolve(d[1]) for d in delays}
    used_nets -= set(POWER)
    fixed = {resolve(INT_PULSE['int_net']), 'osc_loop_open', resolve('F14M')}

    pulled = {resolve(sig) for _ref, sig, _rail in pulls}
    exported = {resolve(n) for n in RENAME}

    # A net becomes a port when it leaves the board: it reaches a connector, it
    # is one of the analogue interface nets listed in RENAME, or it is held by a
    # pull-up and so is really an external input (keyboard, /RESET, /NMI …).
    # A driven net that nothing reads is just an unused output, and an
    # undriven input pin that nothing feeds is a floating TTL input, which
    # reads as a one -- neither becomes a port.
    inputs, outputs, bidir, floating = [], [], [], []
    for net in sorted(used_nets):
        if net in fixed:
            continue
        external = net in conn_nets or net in exported
        if net in bussed and net in conn_nets:
            bidir.append(net)
        elif net not in driven:
            # A pull-up on an undriven net means a real external input
            # (keyboard column, /RESET button, /NMI …).  A pull-up on a net
            # that *is* driven is just a bus terminator and stays internal.
            if external or net in pulled:
                inputs.append(net)
            else:
                floating.append(net)
        elif external:
            outputs.append(net)

    portname = {}
    seen = set()
    for net in inputs + outputs + bidir:
        nm = ident(RENAME.get(net, net))
        while nm in seen:
            nm += '_'
        seen.add(nm)
        portname[net] = nm

    def wname(net):
        net = resolve(net)
        if net == 'VCC':
            return "1'b1"
        if net == 'GND':
            return "1'b0"
        return portname.get(net, ident(net))

    # ------------------------------------------------------------------ output
    o = []
    o.append('// ' + '-' * 75)
    o.append('// %s -- structural Verilog for the Krasnodar-48 (ZX Spectrum clone).' % top)
    o.append('//')
    o.append('// Generated by Tools/easyeda_to_verilog.py from')
    o.append('//   Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json')
    o.append('// Do not edit by hand -- re-run the generator instead.')
    o.append('//')
    o.append('// Chip models live in Verilog/lib/, the Z80 core in')
    o.append('// Verilog/third_party/tv80/.  Every port of every chip is named')
    o.append('// after its DIP pin.')
    o.append('// ' + '-' * 75)
    o.append('`timescale 1ns / 1ps')
    o.append('')
    o.append('module %s (' % top)
    o.append('    input  clk14,        // 14 MHz, replaces the ZQ1 crystal oscillator')
    decl = ['    input  %s' % portname[n] for n in inputs]
    decl += ['    output %s' % portname[n] for n in outputs]
    decl += ['    inout  %s' % portname[n] for n in bidir]
    o.append(',\n'.join(decl) + ');')
    o.append('')

    internal = sorted(used_nets - set(portname) - set(POWER) - set(floating))
    o.append('  // ---------------------------------------------------------- nets')
    for net in internal:
        note = ''
        if net == 'osc_loop_open':
            note = '   // D8 pin 4, freed by cutting the oscillator ring'
        elif not net.startswith('N$'):
            note = '   // %s' % net
        o.append('  wire %s;%s' % (ident(net), note))
    o.append('')

    if floating:
        o.append('  // ------------ unconnected chip inputs (a floating TTL input reads 1)')
        for net in floating:
            o.append('  wire %s = 1\'b1;   // %s' % (ident(net),
                     ' '.join('%s pin %s' % (r, pin) for r, pin in ic_nets[net])))
        o.append('')

    o.append('  // ------------------------------------- oscillator and interrupt')
    o.append('  assign %s = clk14;' % wname('F14M'))
    if synth:
        o.append('  int_pulse_sync #(.WIDTH_NS(%d)) INT_RC'
                 ' (.clk(clk14), .ksi_n(%s), .int_n(%s));'
                 % (INT_PULSE['width_ns'], wname(INT_PULSE['ksi_net']),
                    ident(INT_PULSE['int_net'])))
    else:
        o.append('  int_pulse #(.WIDTH_NS(%d)) INT_RC (.ksi_n(%s), .int_n(%s));'
                 % (INT_PULSE['width_ns'], wname(INT_PULSE['ksi_net']),
                    ident(INT_PULSE['int_net'])))
    o.append('')

    if pulls:
        o.append('  // ------------------------------------------ pull-up resistors')
        for ref, sig, rail in pulls:
            kind = 'pullup' if rail == 'VCC' else 'pulldown'
            line = '  %s (%s);%s   // %s' % (kind, wname(sig),
                                             ' ' * max(0, 12 - len(wname(sig))), ref)
            # Synthesis has no notion of a wired pull: every net here is either
            # a top-level input (where the pull is a board-level detail) or is
            # actively driven once the tri-states become multiplexers.
            o.append(('  // ' + line.strip()) if synth else line)
        o.append('')

    if delays:
        o.append('  // ------------------------------- RC timing-correction chains')
        for ref, a, b, tau in delays:
            o.append('  %s #(.DELAY_PS(%d)) %s (.a(%s), .y(%s));'
                     % ('rc_delay_sync' if synth else 'rc_delay', tau,
                        inst_ident(ref), wname(a), ident(b)))
        o.append('')

    o.append('  // --------------------------------------------------------- chips')
    order = sorted(ics, key=lambda r: (r[0], int(re.sub(r'\D', '', r) or 0)))
    for ref in order:
        p = ics[ref]
        mod, _outs, _inouts = DEVICES[p.value]
        params = ''
        if mod == 'dram_x1':
            params = ' #(.ROWBITS(%d))' % DRAM_ROWBITS[p.value]
        outs = DEVICES[p.value][1]
        conns, unused = [], []
        for port in modports[mod]:
            pin = port[1:] if re.match(r'^p\d+$', port) else None
            if pin is None:
                continue
            if pin in p.pins:
                conns.append('.%s(%s)' % (port, wname(p.pins[pin])))
            elif int(pin) in outs:
                conns.append('.%s()' % port)          # unused gate output
                unused.append(pin)
            else:
                conns.append(".%s(1'b1)" % port)      # unused input, floats high
                unused.append(pin)
        for pin in p.pins:
            if 'p' + pin not in modports[mod]:
                warn('%s pin %s (%s) has no port on %s -- dropped'
                     % (ref, pin, p.pins[pin], mod))
        note = p.value + ('' if not unused
                          else '   (pins %s unused)' % ','.join(unused))
        o.append('  %s%s %s (   // %s %s'
                 % (mod, params, inst_ident(ref), ref, note))
        for i in range(0, len(conns), 4):
            o.append('      ' + ', '.join(conns[i:i + 4]) +
                     (',' if i + 4 < len(conns) else ');'))
        o.append('')

    o.append('endmodule')

    open(out_path, 'w', encoding='utf-8').write('\n'.join(o) + '\n')

    # ------------------------------------------------------------------ report
    sys.stderr.write('chips      : %d instances, %d module types\n'
                     % (len(ics), len({DEVICES[p.value][0] for p in ics.values()})))
    sys.stderr.write('nets       : %d internal, %d in, %d out, %d inout, '
                     '%d floating inputs tied high\n'
                     % (len(internal), len(inputs), len(outputs), len(bidir),
                        len(floating)))
    sys.stderr.write('pull-ups   : %d\n' % len(pulls))
    sys.stderr.write('RC delays  : %d\n' % len(delays))
    sys.stderr.write('dropped    : %d passive/analogue parts\n' % len(dropped))
    for ref, val, why in dropped:
        warn('%-5s %-8s %s' % (ref, val, why))
    sys.stderr.write('inputs     : %s\n' % ' '.join(portname[n] for n in inputs))
    sys.stderr.write('outputs    : %s\n' % ' '.join(portname[n] for n in outputs))
    sys.stderr.write('bidir      : %s\n' % ' '.join(portname[n] for n in bidir))
    return out_path


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    convert(args[0], args[1], args[2] if len(args) > 2 else 'krasnodar48',
            synth='--synth' in sys.argv)
