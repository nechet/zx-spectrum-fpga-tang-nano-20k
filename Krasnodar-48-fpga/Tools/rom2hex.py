#!/usr/bin/env python3
"""Binary ROM image -> $readmemh text, one hex byte per line.

    python3 rom2hex.py <in.rom> <out.hex> [--offset N] [--size N]

--offset/--size cut one bank out of a multi-ROM file, e.g. the 48K bank of a
64 KB four-bank image:  --offset 0 --size 16384
"""
import hashlib
import sys

args = [a for a in sys.argv[1:] if not a.startswith('--')]
opts = {}
for a in sys.argv[1:]:
    if a.startswith('--'):
        k, _, v = a[2:].partition('=')
        opts[k] = int(v, 0)
if len(args) < 2:
    sys.exit(__doc__)

data = open(args[0], 'rb').read()
off = opts.get('offset', 0)
size = opts.get('size', len(data) - off)
bank = data[off:off + size]
if len(bank) != size:
    sys.exit('rom2hex: wanted %d bytes at offset %d, file holds %d'
             % (size, off, len(data)))

with open(args[1], 'w') as f:
    f.write('// %s  offset 0x%X  %d bytes\n' % (args[0], off, len(bank)))
    f.write('// sha1 %s\n' % hashlib.sha1(bank).hexdigest())
    for b in bank:
        f.write('%02X\n' % b)

print('%s -> %s  (%d bytes, sha1 %s)'
      % (args[0], args[1], len(bank), hashlib.sha1(bank).hexdigest()))
