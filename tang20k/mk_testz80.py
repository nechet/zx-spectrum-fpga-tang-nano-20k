#!/usr/bin/env python3
"""Build the .z80 loader's test snapshot.

A version 1, compressed, 48K snapshot whose program (testsnap.asm, at 8000)
checks the registers it was started with.  The memory is chosen to exercise
every case of the compression: long runs (split at 255), runs of ED, a lone
ED followed by a byte that starts a run, ED as the very last byte of a run
of others, and plain literal bytes.

Writes
  tb_testz80.bin       the .z80 file (mk_fat_image.py puts it on the test card)
  tb_testz80_mem.hex   the 48K it should leave at 4000-FFFF, for tb_sdmenu.v
"""
import os, random, subprocess, struct, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SP, PC = 0xFF00, 0x8000
REGS = dict(A=0x11, F=0xC5, BC=0x2233, HL=0x4455, DE=0x6677, IX=0x2468, IY=0x1357,
            BC2=0x8899, DE2=0xAABB, HL2=0xCCDD, A2=0xEE, F2=0x5A, I=0x3B, R=0x99)
BORDER = 5

def assemble(src):
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, 'out.bin')
        subprocess.run(['z80asm', '-o', out, src], check=True)
        return open(out, 'rb').read()

def compress(data):
    """The .z80 version 1 scheme: ED ED nn bb for runs of 5+ (or 2+ EDs);
    the byte after a lone ED is never the start of a run."""
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

mem = bytearray(0xC000)                       # 4000-FFFF, index = addr - 4000
def put(addr, bs): mem[addr - 0x4000: addr - 0x4000 + len(bs)] = bs

random.seed(48)
put(0x4000, bytes(random.randrange(256) for _ in range(256)))   # literals
put(0x4100, b'\xAA' * 1000)                                     # a run over 255
put(0x5800, b'\x38' * 768)                                      # attributes
put(0x9000, b'\xED' * 2 + b'\x01' + b'\xED' * 300 + b'\x02')    # runs of ED
put(0x9200, b'\xED' + b'\x00' * 20)                             # lone ED, then a run
put(0x9300, b'\x07' * 9 + b'\xED' + b'\x03')                     # ED after a run
put(0x9400, bytes(random.randrange(256) for _ in range(256)))   # more literals
put(0xFFF0, bytes(range(0xF0, 0x100)))                          # up to the very end

code = assemble(os.path.join(HERE, 'testsnap.asm'))
put(PC, code)
r = REGS
expect = struct.pack('<12H', SP, r['A'] << 8 | r['F'], r['HL'], r['BC'], r['DE'], r['IX'],
                     r['IY'], r['BC2'], r['DE2'], r['HL2'], r['A2'] << 8 | r['F2'],
                     r['I'] << 8 | 0)                 # IFF2 = 0 -> P/V clear
put(0x8F80, expect)

hdr = bytearray(30)
hdr[0], hdr[1] = r['A'], r['F']
struct.pack_into('<HHHH', hdr, 2, r['BC'], r['HL'], PC, SP)
hdr[10], hdr[11] = r['I'], r['R'] & 0x7F
hdr[12] = (r['R'] >> 7) | BORDER << 1 | 0x20       # bit 5: compressed
struct.pack_into('<HHHH', hdr, 13, r['DE'], r['BC2'], r['DE2'], r['HL2'])
hdr[21], hdr[22] = r['A2'], r['F2']
struct.pack_into('<HH', hdr, 23, r['IY'], r['IX'])
hdr[27], hdr[28], hdr[29] = 0, 0, 1                 # DI, IM 1

z80 = bytes(hdr) + compress(mem)
open(os.path.join(HERE, 'tb_testz80.bin'), 'wb').write(z80)
open(os.path.join(HERE, 'tb_testz80_mem.hex'), 'w').write(''.join('%02x\n' % b for b in mem))
print('tb_testz80.bin: %d bytes (48K compressed), program %d bytes at %04X' % (len(z80), len(code), PC))
