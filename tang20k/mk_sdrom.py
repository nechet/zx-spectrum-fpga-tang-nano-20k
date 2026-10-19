#!/usr/bin/env python3
"""Build the SD loader ROM: 32K, the stock 48K ROM (bank 0) and the SD ROM
(bank 1), paged by the 8255's PC5 (see sdbanks.inc).

  python3 mk_sdrom.py [ROM.hex] [OUT.hex]

Reads the stock image (default ../core/spectrum48.hex, which
is left untouched) and assembles two files with z80asm:

  sdrom0.asm  bank 0's doorways, put in its unused area 386E-3CFF (all FF in
              the stock ROM; checked), plus two patches, each checked first:
                0066  JP E_NMI   the NMI entry (was PUSH AF / PUSH HL / LD HL,..)
                0556  JP E_LD    LD-BYTES (was INC D / EX AF,AF' / DEC D)
  sdmenu.asm  bank 1: the menu, the loaders, its side of the doorways; the
              stock ROM's character set is copied in at 3D00, where the menu
              prints from.

MAXF=n in the environment builds the menu with n games per page instead of
19, so a small test card can exercise the paging (tb_sdpage.sh).
"""
import re, subprocess, sys, os, tempfile

here = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '../core/spectrum48.hex')
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, 'spectrum48_sd.hex')
FREE, FREE_END, FONT = 0x386E, 0x3D00, 0x3D00

def labels(path):
    out = {}
    for l in open(path):
        m = re.match(r'(\w+):\s+equ \$([0-9a-fA-F]+)', l)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out

def assemble(name, t, edit=None):
    asm = os.path.join(here, name)
    if edit:
        text = edit(open(asm).read())
        asm = os.path.join(t, name)
        open(asm, 'w').write(text)
    out, err = os.path.join(t, name + '.bin'), os.path.join(t, name + '.err')
    # -L prints the labels on stderr, along with any errors
    subprocess.run(['z80asm', '-I', here, '-L', '-o', out, asm], check=True,
                   stderr=open(err, 'w'))
    return open(out, 'rb').read(), labels(err)

rom = [int(l, 16) for l in open(src) if l.strip() and not l.startswith('//')]
assert len(rom) == 16384, len(rom)
assert rom[0x66:0x69] == [0xF5, 0xE5, 0x2A], 'not the expected NMI handler at 0066'
assert rom[0x556:0x559] == [0x14, 0x08, 0x15], 'not the expected LD-BYTES at 0556'
assert all(b == 0xFF for b in rom[FREE:FREE_END]), 'the free area is not empty'

maxf = os.environ.get('MAXF')
def set_maxf(text):
    return re.sub(r'^MAXF:(\s+)equ\s+\d+', r'MAXF:\1equ     ' + maxf, text, count=1, flags=re.M)

with tempfile.TemporaryDirectory() as t:
    try:
        b0, lab0 = assemble('sdrom0.asm', t)
        b1, lab1 = assemble('sdmenu.asm', t, set_maxf if maxf else None)
    except subprocess.CalledProcessError:
        sys.stderr.write(''.join(open(os.path.join(t, f)).read()
                                 for f in os.listdir(t) if f.endswith('.err')))
        sys.exit('assembly failed')

e_nmi, e_ld = lab0['E_NMI'], lab0['E_LD']
if FREE + len(b0) > FREE_END:
    sys.exit('bank 0 doorways overrun the free area')
if len(b1) > FONT:
    sys.exit('bank 1 is %d bytes, runs into the character set at %04X' % (len(b1), FONT))

bank0 = list(rom)
bank0[0x66:0x69] = [0xC3, e_nmi & 0xFF, e_nmi >> 8]
bank0[0x556:0x559] = [0xC3, e_ld & 0xFF, e_ld >> 8]
bank0[FREE:FREE + len(b0)] = list(b0)

bank1 = [0xFF] * 16384
bank1[:len(b1)] = list(b1)
bank1[FONT:0x4000] = rom[FONT:0x4000]

with open(dst, 'w') as f:
    f.write('// %s + sdrom0.asm (bank 0) + sdmenu.asm (bank 1), by mk_sdrom.py\n'
            % os.path.relpath(src, here))
    f.write(''.join('%02X\n' % b for b in bank0 + bank1))
menu_end = lab1.get('menu_end', len(b1))
print('%s: bank 0 doorways %04X-%04X; bank 1 code %d bytes (%d free before the doorways)' %
      (os.path.basename(dst), FREE, FREE + len(b0) - 1, menu_end - 0x100, lab1['B_NMI'] - menu_end))
