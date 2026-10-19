; -----------------------------------------------------------------------------
; Bank 1 of the SD loader ROM: the games menu, the .Z80 loader and the .TAP
; block loader.  A whole 16K of its own, paged in over the stock ROM through
; the doorways in sdbanks.inc / sdrom0.asm; mk_sdrom.py assembles both and
; writes the 32K image (stock ROM + this).  The original ROM file is not
; changed.
;
; It talks to sd_bridge.v through the board's 8255:
;   port 3F (B)  command        port 5F (C)  bit 4 STROBE out, bit 0 ACK in
;   port 1F (A)  answer         port 7F      mode word 91h
; See sd_bridge.v for the commands.
;
; NMI leaves interrupts disabled (IFF1 = 0), so nothing else runs meanwhile;
; the menu scans the keyboard itself and uses the interrupted program's stack
; (about 40 bytes).  It draws over the whole screen.
;
; Lists the games; ENTER on a .Z80 loads it (version 1 snapshots, 48K), and
; on a .TAP inserts it and runs LOAD "" in a freshly started BASIC: the ROM's
; LD-BYTES then takes its blocks from the card (tapld), so the tape -- and a
; game's own later calls to 0556 -- load instantly.
; -----------------------------------------------------------------------------
        include "sdbanks.inc"
PPA:     equ     1Fh             ; 8255 port A: answer from the bridge
PPB:     equ     3Fh             ; port B: command to the bridge
PPC:     equ     5Fh             ; port C: bit 4 STROBE, bit 0 ACK
FONT:    equ     3D00h           ; the character set: mk_sdrom.py copies the
                                 ; stock ROM's into this bank
MAXF:    equ     19              ; games shown (rows 2..20)
COL_TEXT: equ    38h             ; white paper, black ink
COL_BAR: equ     68h             ; bright cyan paper: the selection
COL_HEAD: equ    4Fh             ; bright blue paper, white ink: title / help

; frame variables, (ix+n)
; the system variables tap uses, and the layout the ROM's START makes on 48K
RAMTOP:  equ     0FF57h          ; the value START gives RAMTOP
P_RAMT:  equ     5CB4h
RAMTOPV: equ     5CB2h           ; the variable RAMTOP itself
UDG:     equ     5C7Bh
RASP:    equ     5C38h
CHARS:   equ     5C36h
ERR_SP:  equ     5C3Dh
CHANS:   equ     5C4Fh
CHANS_0: equ     5CB6h           ; where the channel table goes
DATADD:  equ     5C57h
PROG:    equ     5C53h
PROG_0:  equ     5CCBh           ; the first byte of BASIC, after the channels
VARS:    equ     5C4Bh
E_LINE:  equ     5C59h
K_CUR:   equ     5C5Bh
WORKSP:  equ     5C61h
STKBOT:  equ     5C63h
STKEND:  equ     5C65h
ATTR_P:  equ     5C8Dh
ATTR_T:  equ     5C8Fh
BORDCR:  equ     5C48h
REPDEL:  equ     5C09h
STRMS:   equ     5C10h
LDIR_RET: equ    33C3h           ; LDIR / RET in the stock ROM (end of MOVE-FP)

V_N:     equ     0               ; number of games listed
V_SEL:   equ     1               ; selected row, 0..N-1
V_K:     equ     2               ; byte counter in prent
V_W:     equ     3               ; walk counter in choose
V_E:     equ     4               ; first letter of the extension, from prent
V_TOP:   equ     5               ; index of the game on the first row (pages of MAXF)
V_MORE:  equ     6               ; 00 if there are games after this page

        org     0
        ld      a, 2            ; never run: reset always starts in bank 0
        out     (0FEh), a       ; (red border if it ever does)
        di
        halt
        defs    0038h - $, 0FFh
        ei                      ; no interrupts in bank 1: it runs with DI
        ret
        defs    0066h - $, 0FFh
        retn                    ; F12 again while the menu runs
        defs    0100h - $, 0FFh

; E_NMI (bank 0) has already pushed AF and set mode 91h
menu:   push    bc              ; save everything the interrupted program had
        push    de
        push    hl
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        ex      af, af'
        push    af
        ld      ix, -8          ; 8 bytes of variables on the stack
        add     ix, sp
        ld      sp, ix

        call    sync
        call    frame

        ld      a, 1            ; mount the card (allow ~20 s for a slow card)
        ld      h, 14
        call    xfer_t
        jp      c, noif
        or      a
        jp      nz, cerr

        ld      (ix+V_TOP), 0
        ld      (ix+V_SEL), 0

; list one page: walk past V_TOP games, then show up to MAXF
list:   ld      (ix+V_N), 0
        ld      a, (ix+V_TOP)
        ld      (ix+V_W), a
        ld      a, 2            ; first
ls1:    call    xfer
        jp      c, noif
        cp      1
        jr      z, lend         ; no more
        or      a
        jp      nz, cerr
        ld      a, (ix+V_W)
        or      a
        jr      z, lshow
        dec     (ix+V_W)        ; still before this page
        jr      lnext
lshow:  ld      a, (ix+V_N)
        add     a, 2
        ld      d, a
        ld      e, 2
        call    prent
        inc     (ix+V_N)
        ld      a, (ix+V_N)
        cp      MAXF
        jr      z, lfull
lnext:  ld      a, 3            ; next
        jr      ls1
lfull:  ld      a, 3            ; page full: is there one more?
        call    xfer
        jr      lst
lend:   ld      a, 1
lst:    ld      (ix+V_MORE), a
        ld      a, (ix+V_N)
        or      a
        jp      z, empty

sel:    ld      b, COL_BAR
        call    hilite
        call    getkey
        push    af
        ld      b, COL_TEXT
        call    hilite
        pop     af
        bit     3, a
        jp      nz, quit        ; SPACE / Esc
        bit     2, a
        jr      nz, choose      ; ENTER
        bit     0, a
        jr      z, s_dn
        ld      a, (ix+V_SEL)   ; up
        or      a
        jr      nz, s_up
        ld      a, (ix+V_TOP)   ; top row: the previous page, if any
        or      a
        jr      z, sel
        sub     MAXF
        ld      (ix+V_TOP), a
        ld      (ix+V_SEL), MAXF-1
        jr      page
s_up:   dec     (ix+V_SEL)
        jr      sel
s_dn:   ld      a, (ix+V_SEL)   ; down
        inc     a
        cp      (ix+V_N)
        jr      c, s_dn1
        ld      a, (ix+V_MORE)  ; last row: the next page, if any
        or      a
        jr      nz, sel
        ld      a, (ix+V_TOP)
        add     a, MAXF
        ld      (ix+V_TOP), a
        ld      (ix+V_SEL), 0
page:   call    frame
        jp      list
s_dn1:  ld      (ix+V_SEL), a
        jr      sel

; ENTER: walk to the chosen game -- first, then next V_TOP + V_SEL times --
; show it on the bottom line, and load it if it is a .Z80.
choose: ld      a, 2
        call    xfer
        jp      c, noif
        ld      a, (ix+V_TOP)
        add     a, (ix+V_SEL)
        ld      (ix+V_W), a
ch1:    ld      a, (ix+V_W)
        or      a
        jr      z, ch2
        ld      a, 3
        call    xfer
        jp      c, noif
        dec     (ix+V_W)
        jr      ch1
ch2:    ld      de, 1700h
        ld      hl, t_pick
        call    prstr
        call    prent
        ld      a, (ix+V_E)
        cp      'T'
        jr      z, tap
        cp      'Z'
        jp      z, z80
        jp      sel             ; .SNA: not yet

; --- .TAP: insert it, start BASIC afresh and run LOAD "" -------------------------
; What the stock ROM does at power-on (START, 11CB-12B1) -- minus the memory
; test and the copyright message -- and then what its editor does when ENTER
; is pressed on a typed LOAD "": the line goes into E_LINE and the ROM's main
; loop carries on from 12B4, where the editor returns to.  The interrupted
; program, and any BASIC in memory, is dropped, as at power-on: whatever was
; running (a game, the editor, an INPUT) need not be in a state to come back
; to.  The steps below are the ROM's own, in its order; the addresses on the
; right are where each is in the stock ROM.  The ROM's memory test leaves RAM
; zeroed and some of START relies on that, so the system variables are
; cleared first.
tap:    ld      a, 4            ; open: the stream starts at the first block
        call    xfer
        jp      c, noif
        ld      a, 7            ; and tell the bridge it is a tape
        call    xfer
        jp      c, noif
        ld      a, 7            ;                                       11CC
        out     (0FEh), a       ; white border
        ld      sp, RAMTOP - 1  ; the ROM's stack; the menu's is abandoned 1228
        im      1               ; (a game may have left IM 2)          122E
        ld      iy, 5C3Ah       ; IY -> ERR_NR, as the ROM keeps it     1230
        ld      hl, 5C00h       ; the system variables, zero
        ld      de, 5C01h
        ld      bc, PROG_0 - 5C00h
        ld      (hl), 0
        ldir
        ld      hl, 0FFFFh
        ld      (P_RAMT), hl    ;                                       1200
        ld      hl, 3EAFh       ; the UDGs: the font's letters A-U       1203
        ld      de, 0FFFFh      ; (bank 1 has the font, at the same address)
        ld      bc, 0A8h
        lddr
        ld      hl, RAMTOP + 1
        ld      (UDG), hl       ;                                       120E
        ld      hl, 0040h
        ld      (RASP), hl      ; RASP 40h, PIP 0                       1215
        ld      hl, RAMTOP
        ld      (RAMTOPV), hl   ;                                       1219
        ld      (hl), 3Eh       ; the marker the ROM leaves at RAMTOP   1225
        ld      hl, 3C00h
        ld      (CHARS), hl     ;                                       121F
        ld      hl, RAMTOP - 3
        ld      (ERR_SP), hl    ;                                       122B
        ld      hl, CHANS_0
        ld      (CHANS), hl     ;                                       1238
        ex      de, hl
        ld      hl, 15AFh       ; the channel table, in bank 0's ROM     123B
        ld      bc, 21
        ld      ix, LDIR_RET
        call    far0
        ld      hl, PROG_0 - 1
        ld      (DATADD), hl    ;                                       1246
        inc     hl
        ld      (PROG), hl      ;                                       124A
        ld      (VARS), hl      ;                                       124D
        ld      (hl), 80h       ; no program, no variables              1250
        inc     hl
        ld      (E_LINE), hl    ; SET-MIN, below, finishes the layout   1253
        ld      a, 38h          ; black on white                        1265
        ld      (ATTR_P), a
        ld      (ATTR_T), a
        ld      (BORDCR), a
        ld      hl, 0523h
        ld      (REPDEL), hl    ;                                       1273
        ld      a, 0FFh
        ld      (5C00h), a      ; KSTATE: no key in either set          1276
        ld      (5C04h), a
        ld      hl, 15C6h       ; the stream table, from bank 0          127C
        ld      de, STRMS
        ld      bc, 14
        ld      ix, LDIR_RET
        call    far0
        set     1, (iy+1)       ; FLAGS                                 1287
        ld      ix, 0EDFh       ; CLEAR-PRB                             128B
        call    far0
        ld      (iy+31h), 2     ; DF_SZ                                 128E
        ld      ix, 0D6Bh       ; CLS                                   1292
        call    far0
        set     5, (iy+2)       ; TV_FLAG: the lower screen to clear     129C
        ld      ix, 16B0h       ; SET-MIN: E_LINE = 0D 80, the rest after 12A9
        call    far0
        xor     a               ; CHAN-OPEN #0: the keyboard / lower screen 12AC
        ld      ix, 1601h
        call    far0
        ; what the editor would hand over: LOAD "" (LOAD is token EF)
        ld      hl, (E_LINE)
        ld      (hl), 0EFh
        inc     hl
        ld      (hl), '"'
        inc     hl
        ld      (hl), '"'
        inc     hl
        ld      (K_CUR), hl     ; the cursor at the end of the line
        ld      (hl), 0Dh
        inc     hl
        ld      (hl), 80h
        inc     hl
        ld      (WORKSP), hl
        ld      (STKBOT), hl
        ld      (STKEND), hl
        ld      hl, 12B4h       ; on, as if from the editor: syntax check,
        push    hl              ; then run the line
        push    af
        jp      X_EIRET-4       ; POP AF / EI / RET, in bank 0

; far0: call the stock ROM's routine at IX from bank 1, and come back.  A, BC,
; DE, HL go in, and come back as the routine leaves them, F too.  Out through
; X_RET (POP AF / RET: to the routine), whose RET lands on E_BK (bank 0's
; PUSH AF / LD A,91h / OUT), which falls into B_BK here: POP AF / RET.
far0:   push    hl
        ld      hl, E_BK
        ex      (sp), hl        ; the routine returns to E_BK ...
        push    ix              ; ... and is entered by X_RET's RET
        push    af
        jp      X_RET-4

; --- LD-BYTES from the card --------------------------------------------------------
; Entered from E_LD (bank 0) in place of the ROM's LD-BYTES, with its inputs:
; IX = where, DE = how many, A = the flag byte, carry = LOAD (clear: VERIFY),
; AF also on the stack.  Without a tape inserted it hands over to the real
; routine.  With one: the next block of the .TAP (2-byte length, flag, data,
; XOR checksum) -- a wrong flag skips the block and fails, as on a tape;
; a block longer than DE+2 has its tail skipped (the ROM stops reading too),
; a shorter one fails.  Exits with IX advanced and DE counted down, and the
; carry set if all went well, through SA/LD-RET as the ROM does.
tapld:  call    sync
        ld      a, 6            ; is a tape inserted?
        call    xfer
        jp      c, X_ROMLD-4
        or      a
        jp      nz, X_ROMLD-4   ; no: the real LD-BYTES, from the tape input
        push    de              ; the count the ROM wants
        call    rdde            ; block length
        ex      de, hl          ; HL = bytes left in the block
        pop     de              ; DE = wanted
        ld      a, h
        or      l
        jr      z, tfail        ; past the end of the tape
        call    rdb             ; the flag byte
        dec     hl
        pop     bc              ; B = the flag wanted, C bit 0 = LOAD
        push    bc
        cp      b
        jr      nz, tskip       ; not this block
        ld      c, a            ; C = running XOR, from the flag
tl1:    ld      a, d            ; DE bytes wanted ...
        or      e
        jr      z, tsum
        ld      a, h            ; ... while more than the checksum is left
        or      a
        jr      nz, tl2
        ld      a, l
        cp      2
        jr      c, tskip        ; the block is too short
tl2:        call    rdb
        dec     hl
        ld      b, a
        xor     c
        ld      c, a
        ld      a, b
        ex      (sp), hl        ; L = the saved F: LOAD or VERIFY?
        bit     0, l
        ex      (sp), hl
        jr      z, tver
        ld      (ix+0), a
        jr      tnext
tver:   cp      (ix+0)
        jr      nz, tskip       ; VERIFY found a difference
tnext:  inc     ix
        dec     de
        jr      tl1
tsum:   call    rdb             ; the checksum byte
        dec     hl
        xor     c
        jr      nz, tskip
        call    tdrop           ; the rest of the block, if longer
        pop     af
        scf                     ; loaded and checked
        push    af
        jp      X_LDRET-4
tskip:  call    tdrop
tfail:  pop     af
        and     a               ; carry clear: failed
        push    af
        jp      X_LDRET-4
; tdrop: read and discard the HL bytes left in the block
tdrop:  ld      a, h
        or      l
        ret     z
        call    rdb
        dec     hl
        jr      tdrop

; --- .Z80 loader ----------------------------------------------------------------
; Version 1 header (30 bytes), then 48K from 4000, ED ED nn bb = nn x bb when
; flags bit 5 is set.  Everything from 4000 up is overwritten, so nothing is
; kept in RAM: SP moves to the game's own stack as soon as it is known (calls
; only touch the few free bytes under it), and at the end the file is opened
; again to re-read each register field as it is needed.
z80:    ld      a, 6
        call    hdr
        call    rdde            ; PC; 0 = version 2 or 3
        ld      a, d
        or      e
        jr      nz, z1
        ld      de, 1700h
        ld      hl, t_ver
        call    prstr
        jp      sel
z1:     call    rdde            ; SP
        call    rdb             ; I
        call    rdb             ; R
        call    rdb             ; flags
        ld      c, a
        ld      b, 17           ; on to offset 30, the memory
z2:     call    rdb
        djnz    z2
        ex      de, hl
        ld      sp, hl          ; the game's stack from here on
        ld      hl, 4000h
zl:     call    rdb
        bit     5, c
        jr      z, zput         ; not compressed
        cp      0EDh
        jr      nz, zput
        call    rdb
        cp      0EDh
        jr      z, zrun
        ld      (hl), 0EDh      ; a lone ED; the byte after it is literal
        inc     hl
zput:   ld      (hl), a
        inc     hl
        ld      a, h
        or      l
        jr      nz, zl          ; until past FFFF
        jr      zreg
zrun:   call    rdb             ; ED ED count byte
        ld      b, a
        call    rdb
zr1:    ld      (hl), a
        inc     hl
        ld      e, a
        ld      a, h
        or      l
        jr      z, zreg
        ld      a, e
        djnz    zr1
        jr      zl

zreg:   ld      a, 10
        call    hdr
        call    rdb             ; I
        ld      i, a
        call    rdb             ; R, bits 0..6
        ld      e, a
        call    rdb             ; flags: bit 0 = R bit 7, bits 1..3 = border
        ld      d, a
        rrca
        and     7
        out     (0FEh), a
        ld      a, d
        rrca                    ; bit 0 -> bit 7
        xor     e
        and     80h
        xor     e
        ld      r, a
        ld      a, 21
        call    hdr
        call    rdb             ; A'
        ld      d, a
        call    rdb             ; F'
        ld      e, a
        push    de
        pop     af
        ex      af, af'
        call    rdde            ; IY
        push    de
        pop     iy
        call    rdde            ; IX
        push    de
        pop     ix
        call    rdb             ; IFF1 (read again at the end)
        call    rdb             ; IFF2
        call    rdb             ; IM
        and     3
        im      1               ; IM 0 behaves as IM 1 here: the idle bus is FF
        cp      2
        jr      nz, zr2
        im      2
zr2:    ld      a, 15
        call    hdr
        call    rdde            ; BC'
        ld      b, d
        ld      c, e
        call    rdde            ; DE'
        push    de
        call    rdde            ; HL'
        ex      de, hl
        pop     de
        exx
        ld      a, 6
        call    hdr
        call    rdde            ; PC, under the game's SP, for the last RET
        push    de
        xor     a
        call    hdr
        call    rdb             ; A
        ld      d, a
        call    rdb             ; F
        ld      e, a
        push    de              ; AF under it, for the last POP AF
        call    rdde            ; BC
        ld      b, d
        ld      c, e
        call    rdde            ; HL
        push    de
        ld      a, 13
        call    hdr
        call    rdde            ; DE
        ld      a, 27
        call    hdr
        call    rdb             ; IFF1
        pop     hl
        or      a
        jp      z, X_RET-4      ; POP AF / RET, in bank 0
        jp      X_EIRET-4       ; POP AF / EI / RET: EI takes effect after
                                ; the RET, as on a real Z80

; Loader helpers: they keep BC, DE and HL.  A timeout here -- the card gone
; half-way through -- leaves nothing to return to, so it restarts the machine.
; rdb: next byte of the file.  cmd: command A.  rdde: next two bytes into DE.
rdb:    ld      a, 5
cmd:    push    bc
        push    hl
        call    xfer
        pop     hl
        pop     bc
        ret     nc
        jp      X_RESET-4
rdde:   call    rdb
        ld      e, a
        call    rdb
        ld      d, a
        ret
; hdr: open the file again (from its start) and skip A bytes
hdr:    push    bc
        ld      b, a
        inc     b
        ld      a, 4
        call    cmd
        jr      hd2
hd1:    call    rdb
hd2:    djnz    hd1
        pop     bc
        ret

; --- messages, then wait for a key and leave ---------------------------------
cerr:   cp      0FFh            ; FF: nothing answering -- no interface
        jr      z, noif
        push    af
        ld      de, 0302h
        ld      hl, t_err
        call    prstr
        pop     af
        call    prhex
        jr      waitq
noif:   ld      de, 0302h
        ld      hl, t_noif
        call    prstr
        jr      waitq
empty:  ld      de, 0302h
        ld      hl, t_none
        call    prstr
waitq:  call    getkey
quit:   ld      hl, 8           ; drop the variables
        add     hl, sp
        ld      sp, hl
        pop     af
        ex      af, af'
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        jp      X_RETN-4        ; POP AF / RETN, in bank 0

; --- talking to the bridge -----------------------------------------------------
; xfer: A = command -> A = answer, carry set if nothing answered (~3 s).
; xfer_t: the same with H = timeout in units of ~1.5 s.  Uses BC, HL.
xfer:   ld      h, 2
xfer_t: out     (PPB), a        ; command on port B
        in      a, (PPC)        ; toggle STROBE (PC4); writing port C
        xor     10h             ; leaves its input half alone
        out     (PPC), a
        ld      bc, 0
xw:     in      a, (PPC)        ; wait for ACK (PC0) = STROBE (PC4)
        ld      l, a
        rrca
        rrca
        rrca
        rrca
        xor     l
        and     1
        jr      z, xok
        dec     bc
        ld      a, b
        or      c
        jr      nz, xw
        dec     h
        jr      nz, xw
        scf
        ret
xok:    in      a, (PPA)        ; the answer; OR clears carry
        or      a
        ret
; sync: after the mode word, wait for ACK to settle (the bridge answers the
; STROBE change the mode word may have caused).
sync:   ld      h, 1
        ld      bc, 0
        jr      xw

; --- keyboard: bit 0 up (7), 1 down (6), 2 ENTER, 3 SPACE -------------------------
; The PS/2 cursor keys are CAPS+5..8, so they read as 6 and 7 here.
getkey: call    keys            ; wait for everything released
        or      a
        jr      nz, getkey
        call    pause
gk1:    call    keys            ; then for a press
        or      a
        jr      z, gk1
        push    af
        call    pause
        pop     af
        ret
keys:   ld      c, 0
        ld      a, 0EFh         ; row 0 9 8 7 6
        in      a, (0FEh)
        bit     3, a
        jr      nz, k1
        set     0, c
k1:     bit     4, a
        jr      nz, k2
        set     1, c
k2:     ld      a, 0BFh         ; row ENTER L K J H
        in      a, (0FEh)
        bit     0, a
        jr      nz, k3
        set     2, c
k3:     ld      a, 7Fh          ; row SPACE SYM M N B
        in      a, (0FEh)
        bit     0, a
        jr      nz, k4
        set     3, c
k4:     ld      a, c
        ret
pause:  ld      bc, 2000        ; ~20 ms: key bounce
pa1:    dec     bc
        ld      a, b
        or      c
        jr      nz, pa1
        ret

; --- screen ----------------------------------------------------------------------
; frame: clear the screen, title and help bars
frame:  call    cls
        ld      de, 0000h
        ld      hl, t_head
        call    prstr
        ld      de, 1600h
        ld      hl, t_help
        jp      prstr
cls:    ld      hl, 4000h       ; pixels off
        ld      de, 4001h
        ld      bc, 17FFh
        ld      (hl), 0
        ldir
        ld      hl, 5800h       ; colours
        ld      de, 5801h
        ld      bc, 2FFh
        ld      (hl), COL_TEXT
        ldir
        ld      b, COL_HEAD     ; title and help bars
        ld      a, 0
        call    bar
        ld      a, 22
        call    bar
        ld      a, 1            ; blue border
        out     (0FEh), a
        ret
; hilite: colour the selected game's row with attribute B
hilite: ld      a, (ix+V_SEL)
        add     a, 2
; bar: colour row A with attribute B
bar:    ld      l, a
        ld      h, 0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      de, 5800h
        add     hl, de
        ld      c, 32
bar1:   ld      (hl), b
        inc     hl
        dec     c
        jr      nz, bar1
        ret

; prent: read the 15-byte entry from the bridge, print it at D,E as NAME.EXT
prent:  ld      (ix+V_K), 0
pe1:    push    de
        ld      a, 5
        call    xfer
        pop     de
        ret     c
        ld      c, a
        ld      a, (ix+V_K)
        cp      11
        jr      nc, pe3         ; the size bytes are not printed
        cp      8
        jr      nz, pe2
        ld      (ix+V_E), c     ; the extension's first letter, for choose
        ld      a, '.'
        call    prch
pe2:    ld      a, c
        call    prch
pe3:    inc     (ix+V_K)
        ld      a, (ix+V_K)
        cp      15
        jr      nz, pe1
        ret

; prstr: print the 0-terminated string at HL at D,E
prstr:  ld      a, (hl)
        or      a
        ret     z
        call    prch
        inc     hl
        jr      prstr

; prhex: print A as two hex digits at D,E
prhex:  push    af
        rrca
        rrca
        rrca
        rrca
        call    prnib
        pop     af
prnib:  and     0Fh
        add     a, '0'
        cp      '9' + 1
        jr      c, prch
        add     a, 7
; prch: print character A at row D, column E from the ROM font; E moves on.
; Keeps BC, HL.  Screen address: 010R R000 | RRRC CCCC, R = row, C = column.
prch:   push    bc
        push    hl
        cp      20h
        jr      c, pc0
        cp      80h
        jr      c, pc1
pc0:    ld      a, '?'
pc1:    ld      l, a            ; font address = 3C00 + 8 * char
        ld      h, 0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      bc, FONT - 100h
        add     hl, bc
        push    de
        ex      de, hl          ; DE = font, HL = row/column
        ld      a, h
        and     18h
        or      40h
        ld      b, a
        ld      a, h
        and     07h
        rrca
        rrca
        rrca
        or      l
        ld      l, a
        ld      h, b
        ld      b, 8
pc2:    ld      a, (de)
        ld      (hl), a
        inc     de
        inc     h
        djnz    pc2
        pop     de
        inc     e
        pop     hl
        pop     bc
        ret

t_head: db      " KRASNODAR-48  SD CARD LOADER", 0
t_help: db      " 7/6/arrows  ENTER  SPACE=exit", 0
t_pick: db      " chosen: ", 0
t_err:  db      "SD card error ", 0
t_noif: db      "No SD interface", 0
t_none: db      "No games on the card", 0
t_ver:  db      " Z80 v2/v3: not supported yet ", 0
menu_end:

; --- doorways back into bank 0 (sdbanks.inc) -------------------------------------
        defs    B_NMI - $, 0FFh
        jp      menu
        defs    B_LD - $, 0FFh
        jp      tapld
        defs    X_RETN - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    X_RET - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    X_EIRET - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    X_ROMLD - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    X_LDRET - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    X_RESET - 4 - $, 0FFh
        ld      a, MODE_OFF
        out     (PCTL), a
        defs    B_BK - $, 0FFh
        pop     af              ; back from a stock ROM routine (far0)
        ret
