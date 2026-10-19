; Fifth test ROM: the upper 32K of RAM (8000-FFFF, D23-D30).
;
; Writes known values, reads them back, and shows the verdict on the border:
; green = every check passed, red = a read came back wrong.  Blue while still
; running.  Three checks, chosen to be short enough to simulate:
;
;   1. 8000-80FF and FF00-FFFF filled with two different patterns: the lowest
;      and highest pages, every column address.
;   2. an address-bit walk: 8000h, then 8000h + 2^k for k = 0..14, each with
;      its own value, all written before any is read back.  A stuck or
;      swapped address line makes two of them land in the same cell, and the
;      earlier one reads back wrong.
;   3. 4000h (video RAM) and C000h differ only in A15: video RAM must not
;      alias onto the upper RAM, or the other way round.
        org 0000h
        di
        ld      a, 1            ; blue: running
        out     (0FEh), a

        ld      hl, 8000h       ; 1. page 80: L xor 5A
f1:     ld      a, l
        xor     5Ah
        ld      (hl), a
        inc     l
        jr      nz, f1
        ld      hl, 0FF00h      ;    page FF: not L
f2:     ld      a, l
        cpl
        ld      (hl), a
        inc     l
        jr      nz, f2

        ld      hl, 8000h       ;    read both back
v1:     ld      a, l
        xor     5Ah
        cp      (hl)
        jr      nz, fail
        inc     l
        jr      nz, v1
        ld      hl, 0FF00h
v2:     ld      a, l
        cpl
        cp      (hl)
        jr      nz, fail
        inc     l
        jr      nz, v2

        ld      a, 77h          ; 3. video RAM at 4000h
        ld      (4000h), a

        ld      ix, walk        ; 2. write the walk, value = index * 11h + 3
        ld      b, NWALK
        ld      c, 3
w1:     ld      l, (ix+0)
        ld      h, (ix+1)
        ld      (hl), c
        ld      a, c
        add     a, 11h
        ld      c, a
        inc     ix
        inc     ix
        djnz    w1

        ld      ix, walk        ;    and read it back
        ld      b, NWALK
        ld      c, 3
r1:     ld      l, (ix+0)
        ld      h, (ix+1)
        ld      a, (hl)
        cp      c
        jr      nz, fail
        ld      a, c
        add     a, 11h
        ld      c, a
        inc     ix
        inc     ix
        djnz    r1

        ld      a, (4000h)      ; 3. video RAM untouched by the C000h write
        cp      77h
        jr      nz, fail

        ld      a, 4            ; green: pass
        out     (0FEh), a
        jr      $
fail:   ld      a, 2            ; red: fail
        out     (0FEh), a
        jr      $

walk:   dw      8000h, 8001h, 8002h, 8004h, 8008h, 8010h, 8020h, 8040h
        dw      8080h, 8100h, 8200h, 8400h, 8800h, 9000h, 0A000h, 0C000h
NWALK:  equ     16
