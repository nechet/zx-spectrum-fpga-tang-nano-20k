; -----------------------------------------------------------------------------
; Doorways between the two ROM banks (included by sdrom0.asm and sdmenu.asm).
;
; The bank is chosen by the 8255's PC5 (top.v): mode word 91h makes port C an
; output, PC5 low, and bank 1 (the SD ROM) appears; mode word 9Bh -- the reset
; state, all inputs -- lets PC5 float high and brings back bank 0, the stock
; ROM.  The switch happens between two instructions: the OUT is fetched from
; one bank and the next opcode from the other.  So each doorway is a pair of
; addresses that line up, one in each bank:
;
;   in:  bank 0 E_xxx: ... OUT (7Fh),A (91h)  ->  bank 1 at the next address
;   out: bank 1 X_xxx-4: LD A,9Bh / OUT (7Fh),A  ->  bank 0 at X_xxx
;
; All of them live in the stock ROM's unused area, 386E-3CFF.
; -----------------------------------------------------------------------------
PCTL:    equ     7Fh             ; 8255 control port
MODE_SD: equ     91h             ; A in, B out, C upper out, C lower in; bank 1
MODE_OFF: equ    9Bh             ; all inputs, as after reset; bank 0

E_NMI:   equ     386Eh           ; bank 0: PUSH AF / LD A,91h / OUT -> B_NMI
B_NMI:   equ     E_NMI + 5       ; bank 1: JP menu
E_LD:    equ     3873h           ; bank 0: DI / PUSH AF / LD A,91h / OUT -> B_LD
B_LD:    equ     E_LD + 6        ; bank 1: JP tapld

X_RETN:  equ     3880h           ; bank 0: POP AF / RETN      (leave the menu)
X_RET:   equ     3888h           ; bank 0: POP AF / RET       (start a game, DI)
X_EIRET: equ     3890h           ; bank 0: POP AF / EI / RET  (start a game, EI)
X_ROMLD: equ     3898h           ; bank 0: POP AF / the first bytes of LD-BYTES /
                                 ;         JP 0559h          (no tape: the real one)
X_LDRET: equ     38A0h           ; bank 0: POP AF / JP 053Fh  (LD-BYTES' own exit)
X_RESET: equ     38A8h           ; bank 0: RST 0              (card lost mid-load)
E_BK:    equ     38B0h           ; bank 0: PUSH AF / LD A,91h / OUT -> B_BK
B_BK:    equ     E_BK + 5        ; bank 1: POP AF / RET       (back from a stock
                                 ;         ROM routine called by far0)
