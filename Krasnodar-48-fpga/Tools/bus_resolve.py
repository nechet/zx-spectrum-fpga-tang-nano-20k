#!/usr/bin/env python3
"""Turn the shared buses of the generated netlist into explicit logic.

A TTL board resolves its buses electrically: several chips have their outputs
wired together, all but one is in high impedance, and a pull-up resistor holds
the net high when none of them drives.  Verilog can describe that, and
simulation handles it correctly -- but synthesis cannot.  yosys's `tribuf`
pass only resolves tri-states that meet within one module; here they meet at
the top level, after `flatten` has already merged each chip's port net into the
board net.  What survives is a net with six drivers, and yosys reacts by
keeping one and constant-folding the rest.  On this board that silently
deletes the Z80: with `D0..D7` folded to a constant, the instruction register
never varies, so the whole microcode decoder collapses and the CPU with it.

This script rewrites the netlist so no net has more than one driver:

    z80_chip U_D1 (.p14(D0), ...);              becomes    .p14(D0__d0)
    rom_27c128 U_D15 (.p11(D0), ...);                      .p11(D0__d1)
    ...
                                                assign D0 = D0__d0 & D0__d1 & ...;

The AND *is* the pull-up: every chip model releases its output to 1 rather
than to `z`, so a released driver contributes nothing and the net reads high,
exactly as R13-R20 make it on the real board.  A net driven low by two chips at
once would be a bus conflict on the real board too.

`--relax-z` additionally rewrites `1'bz` to `1'b1` in the chip models, which is
what makes "releases to 1" true.  The simulation models are left alone; the
rewritten copies are written to the output directory.

A chip whose bus pins are `inout` -- the Z80 and the 8255 -- needs one more
change, and getting it wrong is subtle enough to be worth spelling out.  Such a
model reads the pin it also drives:

    wire [7:0] di = {p13, p10, p9, p7, p8, p12, p15, p14};
    assign     {p13, p10, p9, p7, p8, p12, p15, p14} = drive ? dout : 8'bz;

If the rewrite simply points those pins at the chip's own driver wires, the CPU
stops reading the bus and starts reading its own output -- 0xFF whenever it is
not writing.  It still synthesises, and it is still recognisably a Z80, just a
quarter of the size, because a decoder whose opcode is always 0xFF folds away.
So for a bidirectional pin the read and the write are separated: the model
keeps `pN` for reading and gains an `output pN__o` for driving, and the netlist
connects `.pN(D0)` alongside `.pN__o(D0__d0)`.

A model may also declare a `clk_sys` port.  That is how a part whose real
clock is a combinational board net gets restructured onto the system clock --
it samples the net instead of being clocked by it, so a race that a slow CMOS
part would ignore does not become a spurious count in an FPGA.  Every instance
of such a module has `.clk_sys(...)` added automatically.

`--connector NET` marks a board-level inout port as a pin on an edge
connector that an off-board device may also pull low -- the 8255's ports, for
an SD-card interface built in the FPGA.  The net gets one more driver, a new
`input NET_ext` (1 = not driving), in the same wired-AND as the chips, and the
port itself becomes an `output` showing the resolved level.  Exactly an
open-collector peripheral on a connector with the board's pull-ups.

`--model-input NAME` gives the board an `input NAME` and connects it to every
instance of a model that declares a port of that name -- a control line that
does not exist on the PCB but that the FPGA's version of a chip needs, as the
ROM's bank select for an SD interface's shadow ROM (a divIDE-style second
EPROM on the same socket).

Usage:
    bus_resolve.py NETLIST.v -o OUTDIR [--relax-z LIB.v ...] [--lib LIB.v ...]
                    [--sys-clock NET] [--export NET ...] [--connector NET ...]
                    [--model-input NAME ...]
"""

import argparse
import os
import re
import sys

# --- parsing ---------------------------------------------------------------
# The generator and the chip models both use ANSI-style port lists, so the
# direction of every port is in the module header.

MODULE_RE = re.compile(r'\bmodule\s+(\w+)\s*(#\s*\([^;]*?\)\s*)?\((.*?)\)\s*;',
                       re.S)
INST_RE = re.compile(r'^[ \t]*(\w+)[ \t]*(#\s*\(.*?\))?[ \t]*(\w+)[ \t]*\((.*?)\)[ \t]*;',
                     re.S | re.M)
CONN_RE = re.compile(r'\.(\w+)\s*\(\s*([^()]*?)\s*\)')
IDENT_RE = re.compile(r'^[A-Za-z_]\w*$')


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def port_directions(text):
    """module name -> {port: 'input'|'output'|'inout'} from ANSI headers."""
    out = {}
    for m in MODULE_RE.finditer(strip_comments(text)):
        name, _params, ports = m.group(1), m.group(2), m.group(3)
        dirs, current = {}, None
        for tok in re.findall(r'\w+', ports):
            if tok in ('input', 'output', 'inout'):
                current = tok
            elif tok in ('wire', 'reg', 'logic', 'signed'):
                continue
            elif current:
                dirs[tok] = current
        out[name] = dirs
    return out


def instances(text):
    """Yield (span, module, instance, [(port, net), ...]) for each instance."""
    for m in INST_RE.finditer(text):
        module, inst, body = m.group(1), m.group(3), m.group(4)
        if module in ('module', 'assign', 'always', 'wire', 'reg', 'input',
                      'output', 'inout', 'if', 'for', 'case'):
            continue
        conns = CONN_RE.findall(body)
        if conns:
            yield m.span(), module, inst, conns


ASSIGN_RE = re.compile(r'assign\s*\{([^}]*)\}\s*=')

# Which pins of the inverter packages are (in, out), and which pins of the gate
# packages are ((in, in), out).  Only what is needed to spot the one-shots.
INVERTERS = {'cd4069': [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)],
             'ttl_7404': [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)]}
NOR_GATES = {'cd4001': [((1, 2), 3), ((5, 6), 4), ((8, 9), 10), ((12, 13), 11)],
             'ttl_7402': [((2, 3), 1), ((5, 6), 4), ((8, 9), 10), ((11, 12), 13)]}


def find_one_shots(text):
    """[(span, out_pin, out_net, in_net)] for every NOR(X, ~X) in the netlist.

    See gate_pulse_sync in counters_sync.v for why these exist and why
    synthesis destroys them.
    """
    inv_of = {}
    insts = list(instances(text))
    for _span, module, inst, conns in insts:
        if module in INVERTERS:
            c = dict(conns)
            for i, o in INVERTERS[module]:
                a, b = c.get('p%d' % i), c.get('p%d' % o)
                if a and b:
                    inv_of[b] = a
    out = []
    for span, module, inst, conns in insts:
        if module not in NOR_GATES:
            continue
        c = dict(conns)
        for ins, outpin in NOR_GATES[module]:
            nets = [c.get('p%d' % i) for i in ins]
            if None in nets:
                continue
            for k in (0, 1):
                if inv_of.get(nets[1 - k]) == nets[k]:
                    out.append((span, 'p%d' % outpin,
                                c.get('p%d' % outpin), nets[k], inst))
    return out


def split_inout_drivers(src, pins):
    """Give `pins` a separate output port for driving, keeping the pin for reads.

    The module keeps `pN` -- now driven by nothing inside, so it reads the board
    net -- and gains `output pN__o`, which carries what the chip drives.
    """
    if not pins:
        return src, 0

    # Redirect every assign that drives only pins of this set to the new
    # ports (a chip may drive its pin groups from several assigns -- the
    # 8255 has one per port), and check that together they cover the set.
    hits = 0
    covered = set()
    out = []
    pos = 0
    for m in ASSIGN_RE.finditer(src):
        lhs = [t for t in re.findall(r'\w+', m.group(1))]
        if not lhs or not set(lhs) <= pins:
            continue
        new = 'assign {%s} =' % ', '.join(p + '__o' for p in lhs)
        out.append(src[pos:m.start()])
        out.append(new)
        pos = m.end()
        hits += 1
        covered |= set(lhs)
    out.append(src[pos:])
    src = ''.join(out)
    if covered != pins:
        sys.exit('no driving assign found for %s' % sorted(pins - covered))

    # Add the new ports at the end of the module header.
    m = MODULE_RE.search(strip_comments(src))
    if not m:
        sys.exit('cannot find module header to extend')
    # Locate the same closing paren in the uncommented text: the header ends at
    # the first ");" after "module".
    start = src.index('module')
    end = src.index(');', start)
    decl = ',\n    output %s' % ', '.join(sorted(pins, key=lambda s: int(s[1:])) and
                                          [p + '__o' for p in
                                           sorted(pins, key=lambda s: int(s[1:]))])
    src = src[:end] + decl + src[end:]
    return src, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('netlist')
    ap.add_argument('-o', '--outdir', required=True)
    ap.add_argument('--lib', action='append', default=[],
                    help='chip models, read for port directions only')
    ap.add_argument('--relax-z', action='append', default=[],
                    help='chip models to copy with 1\'bz rewritten to 1\'b1')
    ap.add_argument('--sys-clock', default='clk14',
                    help="netlist signal to drive every model's clk_sys port")
    ap.add_argument('--connector', action='append', default=[],
                    help='board inout port also driven from off the board '
                         '(wired-AND with a new input NET_ext)')
    ap.add_argument('--model-input', action='append', default=[],
                    help='new board input wired to every model with a port of '
                         'that name (e.g. a shadow ROM bank select)')
    ap.add_argument('--export', action='append', default=[],
                    help='internal net to bring out as an output port <net>_out '
                         '(e.g. the CPU address lines a keyboard matrix needs)')
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    dirs = {}
    srcs = {}
    for path in args.lib + args.relax_z:
        with open(path) as f:
            text = f.read()
        dirs.update(port_directions(text))
        srcs[path] = text

    # --- find which inout pins actually drive a shared net -----------------
    # Done before the models are copied, because a pin that drives one needs
    # its read and write sides separated.  See the note at the top.
    with open(args.netlist) as f:
        net_src = f.read()

    bidir = {}                         # module -> {ports that drive a bus}
    seen = {}
    for _span, module, _inst, conns in instances(net_src):
        if module not in dirs:
            continue
        for port, net in conns:
            if IDENT_RE.match(net) and dirs[module].get(port) in ('output',
                                                                 'inout'):
                seen.setdefault(net, []).append((module, port))
    for net, drv in seen.items():
        if len(drv) > 1 or net in args.connector:
            for module, port in drv:
                if dirs[module][port] == 'inout':
                    bidir.setdefault(module, set()).add(port)

    # --- copy the models, releasing to 1 instead of to z -------------------
    for path in args.relax_z:
        src = srcs[path]
        for module, pins in sorted(bidir.items()):
            if module in port_directions(src):
                src, _ = split_inout_drivers(src, pins)
                for pin in pins:
                    dirs[module][pin + '__o'] = 'output'
                print('%-28s %s: %d bus pins split into read + drive' %
                      (os.path.basename(path), module, len(pins)),
                      file=sys.stderr)
        # `8'bz` means eight z bits, so the replacement must be eight ones --
        # writing 8'b1 would quietly mean 0000_0001 and pull seven bus bits low.
        def ones_b(m):
            width = int(m.group(1)) if m.group(1) else len(m.group(2))
            return "%d'b%s" % (width, '1' * width)

        def ones_h(m):
            width = int(m.group(1)) if m.group(1) else 4 * len(m.group(2))
            return "%d'h%s" % (width, 'F' * ((width + 3) // 4))

        n_before = len(re.findall(r"\d*'[bh][zZ]+", src))
        src = re.sub(r"(\d*)'b([zZ]+)", ones_b, src)
        src = re.sub(r"(\d*)'h([zZ]+)", ones_h, src)
        dest = os.path.join(args.outdir, os.path.basename(path))
        with open(dest, 'w') as f:
            f.write("// Generated by Tools/bus_resolve.py --relax-z from\n"
                    "//   %s\n"
                    "// Tri-state releases are rewritten from z to 1: the board's\n"
                    "// bus pull-ups are modelled as a wired-AND in the netlist.\n"
                    "// Do not edit -- re-run the generator.\n\n" % path)
            f.write(src)
        print('%-28s %3d tri-state releases -> 1' %
              (os.path.basename(path), n_before), file=sys.stderr)

    # --- find the multiply-driven nets -------------------------------------
    with open(args.netlist) as f:
        net_src = f.read()

    unknown = set()
    drivers = {}                       # net -> [(span, port, inst, added)]
    for span, module, inst, conns in instances(net_src):
        if module not in dirs:
            unknown.add(module)
            continue
        for port, net in conns:
            if not IDENT_RE.match(net):
                continue               # a literal such as 1'b1
            if port in bidir.get(module, ()):
                # Bidirectional: `.pN(net)` stays for reading, `.pN__o(...)`
                # is added for driving.
                drivers.setdefault(net, []).append(
                    (span, port + '__o', inst, True))
            elif dirs[module].get(port) in ('output', 'inout'):
                drivers.setdefault(net, []).append((span, port, inst, False))

    # --- gate-delay one-shots ---------------------------------------------
    one_shots = find_one_shots(net_src)

    # Instances of models that want the system clock.
    needs_clk = {m for m, d in dirs.items() if 'clk_sys' in d}
    clk_spans = {}
    in_spans = {}                      # span -> [model input names] (--model-input)
    for span, module, inst, conns in instances(net_src):
        if module in needs_clk and not any(p == 'clk_sys' for p, _ in conns):
            clk_spans.setdefault(span, []).append(inst)
        for name in args.model_input:
            if name in dirs.get(module, {}) and not any(p == name for p, _ in conns):
                in_spans.setdefault(span, []).append(name)
    for name in args.model_input:
        if not any(name in v for v in in_spans.values()):
            sys.exit('--model-input %s: no model has a port of that name' % name)

    # An off-board driver on each connector net (see --connector).
    for net in args.connector:
        if net not in drivers:
            sys.exit('--connector %s: no chip drives that net' % net)
        drivers[net].append((None, None, 'off-board', False))

    shared = {n: d for n, d in drivers.items() if len(d) > 1}
    if unknown:
        print('warning: no port directions for %s' % ', '.join(sorted(unknown)),
              file=sys.stderr)

    # --- rewrite -----------------------------------------------------------
    # Work backwards so earlier spans keep their offsets.
    per_span = {}
    for net, drv in sorted(shared.items()):
        for k, (span, port, inst, added) in enumerate(drv):
            if span is None:
                continue                   # the off-board driver: no instance
            per_span.setdefault(span, []).append(
                (port, net, '%s__d%d' % (net, k), added))

    for span in list(clk_spans) + list(in_spans):
        per_span.setdefault(span, [])

    # The one-shot's gate output is disconnected -- it would only ever be a
    # constant -- and the net is driven by gate_pulse_sync instead.
    for span, outpin, outnet, innet, inst in one_shots:
        per_span.setdefault(span, []).append(
            (outpin, outnet, '%s__folded' % outnet, False))

    out = net_src
    for span in sorted(per_span, reverse=True):
        body = out[span[0]:span[1]]
        extra = []
        if span in clk_spans:
            extra.append('.clk_sys(%s)' % args.sys_clock)
        for name in in_spans.get(span, []):
            extra.append('.%s(%s)' % (name, name))
        for port, net, new, added in per_span[span]:
            if added:
                extra.append('.%s(%s)' % (port, new))
                continue
            pat = re.compile(r'\.%s\s*\(\s*%s\s*\)' % (re.escape(port),
                                                        re.escape(net)))
            body, n = pat.subn('.%s(%s)' % (port, new), body, count=1)
            if n != 1:
                sys.exit('could not rewrite .%s(%s)' % (port, net))
        if extra:
            close = body.rfind(')')
            body = (body[:close].rstrip() + ',\n      ' + ', '.join(extra)
                    + body[close:])
        out = out[:span[0]] + body + out[span[1]:]

    decls = ['', '  // ----------------------------------------- bus resolution',
             '  // Generated by Tools/bus_resolve.py: one wire per driver, ANDed',
             '  // together because the board pulls every bus net up.  See that',
             '  // script for why yosys cannot do this itself.']
    # The per-driver wires are declared at the top of the module, before the
    # instances that drive them: Verilog requires declaration before use, and
    # Icarus 14 enforces it ("Check for declaration after use").
    wdecls = ['', '  // ------------------- bus driver nets (Tools/bus_resolve.py)']
    for net, drv in sorted(shared.items()):
        names = ['%s__d%d' % (net, k) for k in range(len(drv))]
        wdecls.append('  wire %s;   // %s' %
                      (', '.join(names), ' '.join(i for _, _, i, _a in drv)))
        decls.append('  assign %s = %s;' % (net, ' & '.join(names)))
        for k, (span, _p, _i, _a) in enumerate(drv):
            if span is None:
                decls.append('  assign %s__d%d = %s_ext;' % (net, k, net))
    if one_shots:
        decls.append('')
        decls.append('  // ------------------------------------ gate one-shots')
        decls.append('  // NOR(X, ~X) pulses for one gate delay, which is a real')
        decls.append('  // circuit here and a constant after synthesis.  See')
        decls.append('  // gate_pulse_sync in counters_sync.v.')
        for span, outpin, outnet, innet, inst in one_shots:
            wdecls.append('  wire %s__folded;   // %s %s, left unconnected'
                          % (outnet, inst, outpin))
            decls.append('  gate_pulse_sync PULSE_%s (.clk_sys(%s), .a(%s), '
                         '.y(%s));' % (outnet, args.sys_clock, innet, outnet))
    decls.append('')

    # The system clock may not be a net the schematic has; if not, give the
    # module an input for it.  The board's own clock is far too slow to resolve
    # the RC delay lines that generate its DRAM timing.
    if clk_spans and args.sys_clock not in out[:out.index(');')]:
        hdr_end = out.index(');')
        out = (out[:hdr_end] +
               ',\n    // fast clock for the RC delay lines and the memories\n'
               '    input  ' + args.sys_clock + out[hdr_end:])

    # Connector pins: the port shows the resolved level; NET_ext drives it.
    if args.connector:
        hdr_end = out.index(');')
        head = out[:hdr_end]
        for n in args.connector:
            head, k = re.subn(r'\binout(\s+)%s\b' % re.escape(n), r'output\g<1>%s' % n, head)
            if k != 1:
                sys.exit('--connector %s: not an inout port of the board' % n)
        out = (head + ',\n    // off-board drivers on connector pins (--connector), 1 = released\n' +
               ',\n'.join('    input  %s_ext' % n for n in args.connector) +
               out[hdr_end:])

    # Inputs for model-only control lines (--model-input).
    if args.model_input:
        hdr_end = out.index(');')
        out = (out[:hdr_end] + ',\n    // control lines only the FPGA models have (--model-input)\n' +
               ',\n'.join('    input  %s' % n for n in args.model_input) +
               out[hdr_end:])

    # Internal nets brought out for logic outside the board (--export).  The
    # schematic's keyboard connector is off-board, so the CPU address lines
    # that select its rows are otherwise unreachable from the FPGA top level.
    if args.export:
        hdr_end = out.index(');')
        out = (out[:hdr_end] + ',\n    // exported internal nets (--export)\n' +
               ',\n'.join('    output %s_out' % n for n in args.export) +
               out[hdr_end:])
        decls.append('  // ---------------------------------- exported nets (--export)')
        for n in args.export:
            decls.append('  assign %s_out = %s;' % (n, n))
        decls.append('')

    # Driver wires straight after the port list; the logic just before the
    # final endmodule.
    hdr_end = out.index(');') + 2
    out = out[:hdr_end] + '\n' + '\n'.join(wdecls) + '\n' + out[hdr_end:]
    idx = out.rstrip().rfind('endmodule')
    out = out[:idx] + '\n'.join(decls) + '\n' + out[idx:]

    dest = os.path.join(args.outdir, os.path.basename(args.netlist))
    with open(dest, 'w') as f:
        f.write(out)

    for _span, _outpin, outnet, innet, inst in one_shots:
        print('%-28s one-shot %s: %s pulses on the falling edge of %s'
              % (os.path.basename(args.netlist), inst, outnet, innet),
              file=sys.stderr)

    if clk_spans:
        print('%-28s %3d instances given %s as clk_sys'
              % (os.path.basename(args.netlist),
                 sum(len(v) for v in clk_spans.values()), args.sys_clock),
              file=sys.stderr)

    print('%-28s %3d shared nets, %3d drivers' %
          (os.path.basename(args.netlist), len(shared),
           sum(len(d) for d in shared.values())), file=sys.stderr)
    for net, drv in sorted(shared.items()):
        print('    %-8s %s' % (net, ' '.join(i for _, _, i, _a in drv)),
              file=sys.stderr)


if __name__ == '__main__':
    main()
