; -----------------------------------------------------------------------------
; The "game" inside the loader's test snapshot (mk_testz80.py puts it at 8000
; and makes PC point here).  It stores every register as it finds them, then
; compares them with the values the snapshot header asked for (the table
; mk_testz80.py fills in at EXPECT): border green if all match, red if not.
; The memory itself is checked by the testbench, from the loader's writes.
; -----------------------------------------------------------------------------
SAVED:  equ     8F00h           ; 24 bytes, in the order below
EXPECT: equ     8F80h           ; the same 24 bytes as they should be

        org     8000h
start:  ld      (SAVED+0), sp
        push    af
        ld      (SAVED+4), hl
        pop     hl
        ld      (SAVED+2), hl   ; A in the high byte, F in the low
        ld      (SAVED+6), bc
        ld      (SAVED+8), de
        ld      (SAVED+10), ix
        ld      (SAVED+12), iy
        exx
        ld      (SAVED+14), bc
        ld      (SAVED+16), de
        ld      (SAVED+18), hl
        ex      af, af'
        push    af
        pop     hl
        ld      (SAVED+20), hl
        ld      a, i            ; P/V = IFF2
        push    af
        pop     hl
        ld      a, l
        and     4
        ld      l, a
        ld      (SAVED+22), hl  ; I in the high byte, IFF2 (as P/V) in the low

        ld      hl, SAVED
        ld      de, EXPECT
        ld      b, 24
cmp1:   ld      a, (de)
        cp      (hl)
        jr      nz, bad
        inc     hl
        inc     de
        djnz    cmp1
        ld      a, 4            ; green
        out     (0FEh), a
        jr      $
bad:    ld      a, 2            ; red
        out     (0FEh), a
        jr      $
