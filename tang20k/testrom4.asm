; Fourth test ROM: the keyboard.  Reads keyboard row A..G (A9 low: port FDFE)
; for ever and shows it on the border:  A = blue, S = red, D = green; held
; together they mix; nothing pressed = black.  Exercises the whole path --
; PS/2 pins, ps2_keyboard, the exported A8..A15, KD1..KD5, the board's
; keyboard multiplexer and the Z80's IN -- without the real ROM's second of
; start-up.
        org 0000h
        di
loop:   ld      bc, 0FDFEh      ; row A, S, D, F, G
        in      a, (c)          ; D0..D4: 0 = pressed
        cpl
        and     07h             ; A -> 1 blue, S -> 2 red, D -> 4 green
        out     (0FEh), a
        jr      loop
