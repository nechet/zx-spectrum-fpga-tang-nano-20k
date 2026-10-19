#!/usr/bin/env python3
"""Rewrite 48K .z80 snapshots of version 2 or 3 as version 1, the format the
SD menu's loader reads.

    python3 z80tov1.py IN.z80 [IN2.z80 ...] -o OUTDIR

Version 1 files are copied unchanged.  128K snapshots are refused: the
Krasnodar-48 is a 48K machine.  Each output gets an 8.3 name (the FAT32
reader lists short names only), made from the input name and kept unique.

Version 2/3 layout: the 30-byte v1 header with PC = 0, a 2-byte length of
the extra header, the extra header (PC first, then the hardware type), then
memory blocks of: 2-byte compressed length (FFFF = 16384 bytes stored raw),
page number, data.  For a 48K machine page 8 = 4000, 4 = 8000, 5 = C000.
"""
import os, re, struct, sys

PAGES48 = {8: 0x4000, 4: 0x8000, 5: 0xC000}

def unpack(data):
    """ED ED nn bb -> nn x bb (no end marker inside a v2/v3 block)."""
    out, i = bytearray(), 0
    while i < len(data):
        if data[i] == 0xED and i + 1 < len(data) and data[i + 1] == 0xED:
            out += bytes([data[i + 3]]) * data[i + 2]; i += 4
        else:
            out.append(data[i]); i += 1
    return bytes(out)

def pack(data):
    """The v1 scheme, as mk_testz80.py: runs of 5+ (or 2+ EDs), the byte after
    a lone ED never starts a run; end marker 00 ED ED 00."""
    out, i = bytearray(), 0
    while i < len(data):
        b, n = data[i], 1
        while i + n < len(data) and data[i + n] == b and n < 255:
            n += 1
        if n >= 5 or (b == 0xED and n >= 2):
            out += bytes([0xED, 0xED, n, b]); i += n
        elif b == 0xED:
            out.append(0xED); i += 1
            if i < len(data):
                out.append(data[i]); i += 1
        else:
            out.append(b); i += 1
    return bytes(out) + b'\x00\xED\xED\x00'

def to_v1(z):
    hdr = bytearray(z[:30])
    if hdr[6] | hdr[7]:
        return bytes(z)                               # already version 1
    xlen = struct.unpack_from('<H', z, 30)[0]
    pc, hw = struct.unpack_from('<H', z, 32)[0], z[34]
    v3 = xlen != 23
    is48 = hw in ((0, 1, 3) if v3 else (0, 1))       # 48K, + Interface 1, + M.G.T.
    if not is48:
        raise ValueError('not a 48K snapshot (hardware type %d)' % hw)
    mem, p = bytearray(0xC000), 32 + xlen
    while p + 3 <= len(z):
        blen, page = struct.unpack_from('<H', z, p)[0], z[p + 2]; p += 3
        raw = z[p:p + 16384] if blen == 0xFFFF else unpack(z[p:p + blen])
        p += 16384 if blen == 0xFFFF else blen
        if page in PAGES48:
            if len(raw) != 16384:
                raise ValueError('page %d unpacks to %d bytes' % (page, len(raw)))
            a = PAGES48[page] - 0x4000
            mem[a:a + 16384] = raw
    struct.pack_into('<H', hdr, 6, pc)
    if hdr[12] == 0xFF:
        hdr[12] = 1
    hdr[12] |= 0x20                                   # compressed
    return bytes(hdr) + pack(bytes(mem))

def name83(path, used):
    base = re.sub(r'\(.*|\[.*', '', os.path.splitext(os.path.basename(path))[0])
    base = re.sub(r'[^A-Z0-9]', '', base.upper()) or 'GAME'
    for k in range(100):
        n = base[:8] if k == 0 else base[:8 - len(str(k))] + str(k)
        if n not in used:
            used.add(n)
            return n + '.Z80'

def main(argv):
    if '-o' not in argv or argv.index('-o') == len(argv) - 1:
        sys.exit(__doc__)
    i = argv.index('-o'); out = argv[i + 1]; ins = argv[:i] + argv[i + 2:]
    os.makedirs(out, exist_ok=True)
    used = {os.path.splitext(f)[0].upper() for f in os.listdir(out)}
    for f in ins:
        try:
            z = open(f, 'rb').read()
            v1 = to_v1(z)
            n = name83(f, used)
            open(os.path.join(out, n), 'wb').write(v1)
            print('%-12s <- %s (%s)' % (n, os.path.basename(f), 'v1, copied' if v1 == z else 'converted'))
        except Exception as e:
            print('SKIP %s: %s' % (os.path.basename(f), e))

if __name__ == '__main__':
    main(sys.argv[1:])
