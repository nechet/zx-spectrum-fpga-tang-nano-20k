; -----------------------------------------------------------------------------
; Bank 0: the stock 48K ROM's side of the doorways (see sdbanks.inc).
; mk_sdrom.py puts this at 386E, in the ROM's unused area, and patches
;   0066  JP E_NMI    the NMI entry: F12 / button S2 -> the menu
;   0556  JP E_LD     LD-BYTES: a .TAP block from the card, if one is inserted
; Everything else in the stock ROM is unchanged.
; -----------------------------------------------------------------------------
        include "sdbanks.inc"

        org     E_NMI
        push    af
        ld      a, MODE_SD
        out     (PCTL), a       ; -> bank 1, B_NMI

        defs    E_LD - $, 0FFh
        di
        push    af              ; A = flag byte, carry = LOAD (not VERIFY)
        ld      a, MODE_SD
        out     (PCTL), a       ; -> bank 1, B_LD

        defs    X_RETN - $, 0FFh
        pop     af
        retn

        defs    X_RET - $, 0FFh
        pop     af
        ret

        defs    X_EIRET - $, 0FFh
        pop     af
        ei
        ret

        defs    X_ROMLD - $, 0FFh
        pop     af              ; what JP E_LD replaced, then on into the ROM
        inc     d
        ex      af, af'
        dec     d
        jp      0559h

        defs    X_LDRET - $, 0FFh
        pop     af              ; carry = loaded and checked
        jp      053Fh           ; SA/LD-RET: border, BREAK test, EI, RET

        defs    X_RESET - $, 0FFh
        rst     0

        defs    E_BK - $, 0FFh  ; a stock ROM routine called from bank 1
        push    af              ; returns here (far0 in sdmenu.asm)
        ld      a, MODE_SD
        out     (PCTL), a       ; -> bank 1, B_BK
