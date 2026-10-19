#!/usr/bin/env python3
"""Build the .TAP loader's test tape, tb_testtap.bin.

  block 1  flag FF, 5 bytes   a stray data block: LOAD "" must skip it
  block 2  header, PROGRAM    "test", auto-run at line 10
  block 3  the program        10 LOAD "" CODE : RANDOMIZE USR 32768
  block 4  header, CODE       "testcode", 8000h, 2304 bytes
  block 5  the code           a program at 8000 that sums 8100-88FF (a
                              pattern of runs, EDs and noise) and shows
                              green on the border if it matches, red if not

So a LOAD "" exercises the flag check, the skip, the checksum, the ROM's
header handling, an auto-running BASIC program and a CODE load -- every
block through the LD-BYTES trap.  mk_fat_image.py puts it on the test card
as TINY.TAP.
"""
import os, random, struct, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORG, DATA, NDATA = 0x8000, 0x8100, 0x800

def block(flag, data):
    b = bytes([flag]) + bytes(data)
    x = 0
    for c in b:
        x ^= c
    b += bytes([x])
    return struct.pack('<H', len(b)) + b

def header(kind, name, length, p1, p2):
    return block(0x00, bytes([kind]) + name.ljust(10).encode() + struct.pack('<HHH', length, p1, p2))

random.seed(5)
data = (bytes(range(256)) + b'\xED' * 40 + b'\x00' * 300 +
        bytes(random.randrange(256) for _ in range(NDATA)))[:NDATA]
want = sum(data) & 0xFFFF

src = """
        org     %d
        di
        ld      hl, %d
        ld      bc, %d
        ld      de, 0
sum:    ld      a, (hl)
        add     a, e
        ld      e, a
        jr      nc, nc1
        inc     d
nc1:    inc     hl
        dec     bc
        ld      a, b
        or      c
        jr      nz, sum
        ld      hl, %d
        or      a
        sbc     hl, de
        ld      a, 4            ; green
        jr      z, show
        ld      a, 2            ; red
show:   out     (0FEh), a
        jr      $
""" % (ORG, DATA, NDATA, want)
with tempfile.TemporaryDirectory() as t:
    open(os.path.join(t, 'p.asm'), 'w').write(src)
    subprocess.run(['z80asm', '-o', os.path.join(t, 'p.bin'), os.path.join(t, 'p.asm')], check=True)
    prog = open(os.path.join(t, 'p.bin'), 'rb').read()
code = prog + bytes(DATA - ORG - len(prog)) + data

# 10 LOAD "" CODE : RANDOMIZE USR 32768   (tokens; the number with its hidden
# five-byte form, 0E 00 00 lo hi 00)
line = (b'\xEF""\xAF:\xF9\xC0' + b'32768' + b'\x0E\x00\x00' + struct.pack('<H', 32768) +
        b'\x00\x0D')
basic = struct.pack('>H', 10) + struct.pack('<H', len(line)) + line

tap = (block(0xFF, b'junk!') +
       header(0, 'test', len(basic), 10, len(basic)) + block(0xFF, basic) +
       header(3, 'testcode', len(code), ORG, 32768) + block(0xFF, code))
open(os.path.join(HERE, 'tb_testtap.bin'), 'wb').write(tap)
print('tb_testtap.bin: %d bytes, 5 blocks; code %d bytes at %04X, data sum %04X' %
      (len(tap), len(code), ORG, want))
